//
//  SBBConsentManager.m
//  BridgeSDK
//
//  Created by Erin Mounts on 9/23/14.
//
//	Copyright (c) 2014, Sage Bionetworks
//	All rights reserved.
//
//	Redistribution and use in source and binary forms, with or without
//	modification, are permitted provided that the following conditions are met:
//	    * Redistributions of source code must retain the above copyright
//	      notice, this list of conditions and the following disclaimer.
//	    * Redistributions in binary form must reproduce the above copyright
//	      notice, this list of conditions and the following disclaimer in the
//	      documentation and/or other materials provided with the distribution.
//	    * Neither the name of Sage Bionetworks nor the names of BridgeSDk's
//		  contributors may be used to endorse or promote products derived from
//		  this software without specific prior written permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//	DISCLAIMED. IN NO EVENT SHALL SAGE BIONETWORKS BE LIABLE FOR ANY
//	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "SBBConsentManagerInternal.h"
#import "SBBComponentManager.h"
#import "SBBAuthManager.h"
#import "SBBUserManagerInternal.h"
#import "BridgeSDKInternal.h"
#import "SBBConsentSignature.h"
#import "SBBUserSessionInfo.h"
#import "SBBObjectManager.h"

#define CONSENT_API GLOBAL_API_PREFIX @"/consents/signature"
#define CONSENT_SUBPOPULATIONS_API_FORMAT GLOBAL_API_PREFIX @"/subpopulations/%@/consents/signature"

// deprecated APIs
NSString * const kSBBConsentAPI = CONSENT_API;
NSString * const kSBBConsentWithdrawAPI = CONSENT_API  @"/withdraw";

// use these instead
NSString * const kSBBConsentSubpopulationsAPIFormat = CONSENT_SUBPOPULATIONS_API_FORMAT;
NSString * const kSBBConsentSubpopulationsWithdrawAPIFormat = CONSENT_SUBPOPULATIONS_API_FORMAT @"/withdraw";
NSString * const kSBBConsentSubpopulationsEmailAPIFormat = CONSENT_SUBPOPULATIONS_API_FORMAT @"/email";

NSString * const kSBBMimeTypePng = @"image/png";

@implementation SBBConsentManager

+ (instancetype)defaultComponent
{
    static SBBConsentManager *shared;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [self instanceWithRegisteredDependencies];
    });
    
    return shared;
}

- (NSURLSessionTask *)consentSignature:(NSString *)name
                             birthdate:(NSDate *)date
                        signatureImage:(UIImage*)signatureImage
                           dataSharing:(SBBParticipantDataSharingScope)scope
                            completion:(SBBConsentManagerCompletionBlock)completion
{
    return [self consentSignature:name forSubpopulationGuid:gSBBAppStudy birthdate:date signatureImage:signatureImage dataSharing:scope completion:completion];
}

- (NSURLSessionTask *)consentSignature:(NSString *)name
                  forSubpopulationGuid:(NSString *)subpopGuid
                             birthdate:(NSDate *)date
                        signatureImage:(UIImage*)signatureImage
                           dataSharing:(SBBParticipantDataSharingScope)scope
                            completion:(SBBConsentManagerCompletionBlock)completion
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [self.authManager addAuthHeaderToHeaders:headers];
    SBBConsentSignature *consentSignature = [SBBConsentSignature new];
    static NSDateFormatter *birthdateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        birthdateFormatter = [[NSDateFormatter alloc] init];
        [birthdateFormatter setDateFormat:@"yyyy-MM-dd"];
        NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        [birthdateFormatter setLocale:enUSPOSIXLocale];
    });
    
    consentSignature.birthdate = [birthdateFormatter stringFromDate:date];
    consentSignature.name = name;
    [consentSignature setSignatureImage:signatureImage];
    consentSignature.scope = kSBBUserDataSharingScopeStrings[scope];
    
    // convert to json object
    NSDictionary *researchConsent = [self.objectManager bridgeJSONFromObject:consentSignature];
    
    NSString *endpoint = [NSString stringWithFormat:kSBBConsentSubpopulationsAPIFormat, subpopGuid];
    return [self.networkManager post:endpoint headers:headers parameters:researchConsent
                          completion:^(NSURLSessionTask *task, id responseObject, NSError *error) {
                              if (completion) {
                                  completion(responseObject, error);
                              }
                          }];
}

- (NSURLSessionTask *)retrieveConsentSignatureWithCompletion:(SBBConsentManagerRetrieveCompletionBlock)completion
{
    return [self getConsentSignatureForSubpopulation:gSBBAppStudy completion:^(id consentSignature, NSError *error) {
        NSString* name = nil;
        NSString* birthdate = nil;
        UIImage* image = nil;
        
        // parse consent signature dictionary, if we have one
        if ([consentSignature isKindOfClass:[SBBConsentSignature class]]) {
            SBBConsentSignature *cSig = consentSignature;
            name = cSig.name;
            birthdate = cSig.birthdate;
            image = [cSig signatureImage];
        }
        
        // call the completion call back
        if (completion != nil) {
            completion(name, birthdate, image, error);
        }
    }];
}

- (NSURLSessionTask *)getConsentSignatureForSubpopulation:(NSString *)subpopGuid completion:(SBBConsentManagerGetCompletionBlock)completion
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [self.authManager addAuthHeaderToHeaders:headers];
    
    NSString *endpoint = [NSString stringWithFormat:kSBBConsentSubpopulationsAPIFormat, subpopGuid];
    return [self.networkManager get:endpoint headers:headers parameters:nil
                         completion:^(NSURLSessionTask* task, id responseObject, NSError* error) {
                             // call the completion call back
                             if (completion != nil) {
                                 id consentSignature = [self.objectManager objectFromBridgeJSON:responseObject];
                                completion(consentSignature, error);
                             }
                         }];
}

- (NSURLSessionTask *)withdrawConsentWithReason:(NSString *)reason completion:(SBBConsentManagerCompletionBlock)completion
{
    return [self withdrawConsentForSubpopulation:gSBBAppStudy withReason:reason completion:completion];
}

- (NSURLSessionTask *)withdrawConsentForSubpopulation:(NSString *)subpopGuid withReason:(NSString *)reason completion:(SBBConsentManagerCompletionBlock)completion
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [self.authManager addAuthHeaderToHeaders:headers];
    
    NSDictionary *parameters = reason.length ? @{@"reason": reason} : @{};
    NSString *endpoint = [NSString stringWithFormat:kSBBConsentSubpopulationsWithdrawAPIFormat, subpopGuid];
    return [self.networkManager post:endpoint
                             headers:headers
                          parameters:parameters
                          completion:^(NSURLSessionTask *task, id responseObject, NSError *error) {
                              if (completion) {
                                  completion(responseObject, error);
                              }
                          }];
    
}

- (NSURLSessionTask *)emailConsentForSubpopulation:(NSString *)subpopGuid completion:(SBBConsentManagerCompletionBlock)completion
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [self.authManager addAuthHeaderToHeaders:headers];
    
    NSString *endpoint = [NSString stringWithFormat:kSBBConsentSubpopulationsEmailAPIFormat, subpopGuid];
    return [self.networkManager post:endpoint
                             headers:headers
                          parameters:nil
                          completion:^(NSURLSessionTask *task, id responseObject, NSError *error) {
                              if (completion) {
                                  completion(responseObject, error);
                              }
                          }];
    
}

@end
