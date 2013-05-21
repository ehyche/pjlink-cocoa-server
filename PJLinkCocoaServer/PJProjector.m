//
//  PJProjector.m
//  PJLinkCocoaServer
//
//  Created by Eric Hyche on 5/8/13.
//  Copyright (c) 2013 Eric Hyche. All rights reserved.
//

#import "PJProjector.h"
#import "PJLampStatus.h"

const NSUInteger kWarmUpTime = 30;
const NSUInteger kCoolDownTime = 30;

const NSUInteger kMinInputIndex             = 1;
const NSUInteger kMaxInputIndex             = 9;
const NSUInteger kMinNumberOfLamps          = 1;
const NSUInteger kMaxNumberOfLamps          = 8;
const NSUInteger kMaxProjectorNameLength    = 64;
const NSUInteger kMaxManufacturerNameLength = 32;
const NSUInteger kMaxProductNameLength      = 32;
const NSUInteger kMaxOtherInformationLength = 32;
const NSUInteger kMaxCumulativeLightingTime = 99999;

@interface PJProjector()
{
    NSTimer* _powerStatusTransitionTimer;
}

- (void)timerFired:(NSTimer*)timer;
- (void)scheduleTimerWithTimeout:(NSTimeInterval)timeout;

@end

@implementation PJProjector

+ (PJProjector*)sharedProjector {
    static PJProjector* g_sharedProjector = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_sharedProjector = [[PJProjector alloc] init];
    });
    
    return g_sharedProjector;
}

- (id)init {
    self = [super init];
    if (self) {
        _powerStatus = PJPowerStatusStandby;
        _numberOfRGBInputs = 3;
        _numberOfVideoInputs = 2;
        _numberOfDigitalInputs = 3;
        _numberOfStorageInputs = 1;
        _numberOfNetworkInputs = 1;
        _inputType = PJInputTypeRGB;
        _inputNumber = 1;
        _audioMuted = NO;
        _videoMuted = NO;
        _fanError = PJErrorStatusOK;
        _lampError = PJErrorStatusOK;
        _temperatureError = PJErrorStatusOK;
        _coverOpenError = PJErrorStatusOK;
        _filterError = PJErrorStatusOK;
        _otherError = PJErrorStatusOK;
        _numberOfLamps = 1;
        _lampStatuses = [NSArray arrayWithObject:[PJLampStatus lampStatus]];
        _projectorName = @"Projector1";
        _manufacturerName = @"Manufacturer1";
        _productName = @"CocoaPJLinkServer";
        _otherInformation = @"None";
        _class2Compatible = NO;
        _usePassword = NO;
        _password = @"pjlink";
    }

    return self;
}

- (void)handlePowerCommand:(BOOL)on {
    if (on) {
        if (self.powerStatus == PJPowerStatusStandby) {
            // We we are in standby, and we get a power on, then
            // we transition to warm up and set a timer. When the
            // timer fires, then we transition to lamp on
            self.powerStatus = PJPowerStatusWarmUp;
            // Schedule a timer
            [self scheduleTimerWithTimeout:kWarmUpTime];
        }
    } else {
        if (self.powerStatus == PJPowerStatusLampOn) {
            // Transition to cool down
            self.powerStatus = PJPowerStatusCooling;
            // When we are in lamp on status, and we get a power off,
            // then we transition to cooling down, and set a timer.
            // When the timer fires, we transtion to standby
            [self scheduleTimerWithTimeout:kCoolDownTime];
        }
    }
}

- (void)handleInputSwitchWithType:(NSUInteger)type number:(NSUInteger)number {
    self.inputType = type;
    self.inputNumber = number;
}

#pragma mark - PJProjector private methods

- (void)timerFired:(NSTimer*)timer {
    _powerStatusTransitionTimer = nil;
    if (self.powerStatus == PJPowerStatusWarmUp) {
        self.powerStatus = PJPowerStatusLampOn;
    } else if (self.powerStatus == PJPowerStatusCooling) {
        self.powerStatus = PJPowerStatusStandby;
    }
}

- (void)scheduleTimerWithTimeout:(NSTimeInterval)timeout {
    [_powerStatusTransitionTimer invalidate];
    _powerStatusTransitionTimer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                                                   target:self
                                                                 selector:@selector(timerFired:)
                                                                 userInfo:nil
                                                                  repeats:NO];
}

@end
