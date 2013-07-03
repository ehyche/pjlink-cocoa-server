//
//  PJProjector.m
//  PJLinkCocoaServer
//
//  Created by Eric Hyche on 5/8/13.
//  Copyright (c) 2013 Eric Hyche. All rights reserved.
//

#import "PJProjector.h"
#import "PJLampStatus.h"
#import "PJInputInfo.h"
#import "PJErrorStatus.h"

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

NSString* const PJProjectorErrorDomain = @"PJProjectorErrorDomain";

@interface PJProjector()
{
    NSTimer* _powerStatusTransitionTimer;
}

- (void)timerFired:(NSTimer*)timer;
- (void)scheduleTimerWithTimeout:(NSTimeInterval)timeout;
+ (NSError*)errorWithCode:(NSInteger)code localizedDescription:(NSString*)description;

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
        _inputInfo = @[[PJInputInfo inputInfoWithName:@"RGB" numberOfInputs:3],
                       [PJInputInfo inputInfoWithName:@"Video" numberOfInputs:2],
                       [PJInputInfo inputInfoWithName:@"Digital" numberOfInputs:3],
                       [PJInputInfo inputInfoWithName:@"Storage" numberOfInputs:1],
                       [PJInputInfo inputInfoWithName:@"Network" numberOfInputs:1]];
        _inputType = PJInputTypeRGB;
        _inputNumber = 1;
        _audioMuted = NO;
        _videoMuted = NO;
        _errorStatus = @[[PJErrorStatus errorStatusWithName:@"Fan"],
                         [PJErrorStatus errorStatusWithName:@"Lamp"],
                         [PJErrorStatus errorStatusWithName:@"Temperature"],
                         [PJErrorStatus errorStatusWithName:@"Cover Open"],
                         [PJErrorStatus errorStatusWithName:@"Filter"],
                         [PJErrorStatus errorStatusWithName:@"Other"]];
        _fanError = PJErrorStatusOK;
        _lampError = PJErrorStatusOK;
        _temperatureError = PJErrorStatusOK;
        _coverOpenError = PJErrorStatusOK;
        _filterError = PJErrorStatusOK;
        _otherError = PJErrorStatusOK;
        _numberOfLamps = 1;
        _lampStatus = [NSArray arrayWithObject:[PJLampStatus lampStatus]];
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

- (NSUInteger)countOfInputInfo {
    return [_inputInfo count];
}

- (id)objectInInputInfoAtIndex:(NSUInteger)index {
    return [_inputInfo objectAtIndex:index];
}

- (NSUInteger)countOfErrorStatus {
    return [_errorStatus count];
}

- (id)objectInErrorStatusAtIndex:(NSUInteger)index {
    return [_errorStatus objectAtIndex:index];
}

- (NSUInteger)countOfLampStatus {
    return [_lampStatus count];
}

- (id)objectInLampStatusAtIndex:(NSUInteger)index {
    return [_lampStatus objectAtIndex:index];
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

- (BOOL)validatePowerStatus:(id *)ioValue error:(NSError * __autoreleasing *)outError {
    BOOL ret = NO;

    if (ioValue != nil) {
        id powerStatusId = *ioValue;
        if ([powerStatusId isKindOfClass:[NSNumber class]]) {
            NSUInteger powerStatus = [powerStatusId unsignedIntegerValue];
            if (powerStatus <= PJPowerStatusWarmUp) {
                ret = YES;
            }
        }
    }
    if (!ret && outError != NULL) {
        *outError = [PJProjector errorWithCode:PJErrorCodeInvalidPowerStatus localizedDescription:@"Invalid value for power status. Power status must be 0-3."];
    }

    return ret;
}

- (BOOL)validateInputType:(id *)ioValue error:(NSError* __autoreleasing *)outError {
    BOOL ret = NO;

    if (ioValue != nil) {
        id inputTypeId = *ioValue;
        if ([inputTypeId isKindOfClass:[NSNumber class]]) {
            NSUInteger inputType = [inputTypeId unsignedIntegerValue];
            if (inputType >= PJInputTypeRGB && inputType <= PJInputTypeNetwork) {
                ret = YES;
            }
        }
    }
    if (!ret && outError != NULL) {
        *outError = [PJProjector errorWithCode:PJErrorCodeInvalidInputType localizedDescription:@"Invalid value for input type. Input type must be 1-5."];
    }

    return ret;
}

- (BOOL)validateInputNumber:(id *)ioValue error:(NSError* __autoreleasing *)outError {
    BOOL ret = NO;

    if (ioValue != nil) {
        id inputNumId = *ioValue;
        if ([inputNumId isKindOfClass:[NSNumber class]]) {
            NSUInteger inputNum = [inputNumId unsignedIntegerValue];
            // Get the number of inputs for the current input type
            NSUInteger typeIndex = _inputType - 1;
            PJInputInfo* info = [_inputInfo objectAtIndex:typeIndex];
            if (inputNum >= 1 && inputNum <= info.numberOfInputs) {
                ret = YES;
            }
        }
    }
    if (!ret && outError != NULL) {
        *outError = [PJProjector errorWithCode:PJErrorCodeInvalidInputNumber localizedDescription:@"Invalid input number."];
    }

    return ret;
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

+ (NSError*)errorWithCode:(NSInteger)code localizedDescription:(NSString*)description {
    NSDictionary* userInfo = @{ NSLocalizedDescriptionKey : description };
    return [NSError errorWithDomain:PJProjectorErrorDomain code:code userInfo:userInfo];
}

@end
