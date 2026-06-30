#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C @try/@catch. Some Apple APIs (notably AVAudioInputNode.setVoiceProcessingEnabled) signal failure by raising an NSException instead of returning an NSError. Swift's do/catch cannot intercept an NSException, so it propagates to the runtime and aborts the process (SIGABRT). Only Objective-C can catch it. Returns YES on clean completion; on a raised NSException, fills `error` and returns NO.
BOOL PTRunCatchingNSException(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
