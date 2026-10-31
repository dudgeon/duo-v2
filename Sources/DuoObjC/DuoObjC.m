#import "DuoObjC.h"

BOOL DuoCatchException(NS_NOESCAPE void (^block)(void), NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *what = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""];
            *error = [NSError errorWithDomain:@"DuoObjC.exception" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: what}];
        }
        return NO;
    }
}
