//
//  XPCService.m
//  XPCService
//
//  Created by testm1 on 02.04.2021.
//

#import "XPCService.h"

@implementation XPCService

// This implements the example protocol. Replace the body of this class with the implementation of this service's protocol.
- (void)upperCaseString:(NSString *)aString withReply:(void (^)(NSString *))reply {
    NSString *response = [aString uppercaseString];
    reply(response);
}

@end
