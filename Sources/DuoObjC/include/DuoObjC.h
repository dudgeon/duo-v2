#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and catches any Objective-C exception it raises, which Swift can't. Returns NO with
/// `error` describing the exception (its name and reason) when one was raised. For AppKit and
/// AVFoundation calls that report bad state by raising (AVAudioNode's installTap with no input
/// device, F-447): Duo must survive whatever the hardware does.
BOOL DuoCatchException(NS_NOESCAPE void (^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
