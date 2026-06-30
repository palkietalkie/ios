#import "ObjCExceptionCatcher.h"

BOOL PTRunCatchingNSException(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            info[@"ObjCExceptionName"] = exception.name;
            if (exception.reason) {
                info[@"ObjCExceptionReason"] = exception.reason;
            }
            *error = [NSError errorWithDomain:@"com.palkietalkie.ObjCException" code:0 userInfo:info];
        }
        return NO;
    }
}
