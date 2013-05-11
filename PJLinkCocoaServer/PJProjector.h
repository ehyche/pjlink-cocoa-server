//
//  PJProjector.h
//  PJLinkCocoaServer
//
//  Created by Eric Hyche on 5/8/13.
//  Copyright (c) 2013 Eric Hyche. All rights reserved.
//

#import <Foundation/Foundation.h>

enum {
    PJPowerStatusStandby,
    PJPowerStatusLampOn,
    PJPowerStatusCooling,
    PJPowerStatusWarmUp,
    NumPJPowerStatuses
};

enum {
    PJInputTypeRGB,
    PJInputTypeVideo,
    PJInputTypeDigital,
    PJInputTypeStorage,
    PJInputTypeNetwork,
    NumPJInputTypes
};

enum {
    PJErrorStatusOK,
    PJErrorStatusWarning,
    PJErrorStatusError,
    NumPJErrorStatuses
};

enum {
    PJErrorTypeFan,
    PJErrorTypeLamp,
    PJErrorTypeTemperature,
    PJErrorTypeCoverOpen,
    PJErrorTypeFilter,
    PJErrorTypeOther,
    NumPJErrorTypes
};

const NSInteger kMinInputIndex             = 1;
const NSInteger kMaxInputIndex             = 9;
const NSInteger kMinNumberOfLamps          = 1;
const NSInteger kMaxNumberOfLamps          = 8;
const NSInteger kMaxProjectorNameLength    = 64;
const NSInteger kMaxManufacturerNameLength = 32;
const NSInteger kMaxProductNameLength      = 32;
const NSInteger kMaxOtherInformationLength = 32;

@interface PJProjector : NSObject

@property(nonatomic,assign) NSInteger powerStatus;
@property(nonatomic,assign) NSInteger inputType;
@property(nonatomic,assign,getter=isAudioMuted) BOOL audioMuted;
@property(nonatomic,assign,getter=isVideoMuted) BOOL videoMuted;
@property(nonatomic,assign) NSInteger numberOfLamps;
@property(nonatomic,copy) NSString* projectorName;
@property(nonatomic,copy) NSString* manufacturerName;
@property(nonatomic,copy) NSString* productName;
@property(nonatomic,copy) NSString* otherInformation;
@property(nonatomic,assign) BOOL class2Compatible;

- (NSInteger)numberOfInputsForType:(NSInteger)type;
- (void)setNumberOfInputs:(NSInteger)num forType:(NSInteger)type;
- (NSInteger)activeInputForType:(NSInteger)type;
- (void)setActiveInput:(NSInteger)num forType:(NSInteger)type;
- (NSInteger)errorStatusForErrorType:(NSInteger)type;
- (void)setErrorStatus:(NSInteger)status forErrorType:(NSInteger)type;
- (BOOL)isLampOn:(NSInteger)lampIndex;
- (void)setOn:(BOOL)on forLamp:(NSInteger)lampIndex;
- (NSInteger)cumulativeLightingTimeForLamp:(NSInteger)lampIndex;
- (void)setCumulativeLightingTime:(NSInteger)time forLamp:(NSInteger)lampIndex;

@end
