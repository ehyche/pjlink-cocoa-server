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
    PJPowerStatusWarmUp
};

enum {
    PJInputTypeRGB = 1,
    PJInputTypeVideo = 2,
    PJInputTypeDigital = 3,
    PJInputTypeStorage = 4,
    PJInputTypeNetwork = 5
};

enum {
    PJErrorTypeFan,
    PJErrorTypeLamp,
    PJErrorTypeTemperature,
    PJErrorTypeCoverOpen,
    PJErrorTypeFilter,
    PJErrorTypeOther
};

enum {
    PJErrorCodeInvalidPowerStatus = -10,
    PJErrorCodeInvalidInputType   = -11,
    PJErrorCodeInvalidInputNumber = -12
};

NSString* const PJProjectorErrorDomain;

NSString* const PJProjectorDidChangeNotification;

@interface PJProjector : NSObject

+ (PJProjector*)sharedProjector;

@property(nonatomic,assign) NSUInteger powerStatus;
@property(nonatomic,copy) NSArray* inputInfo;
@property(nonatomic,assign) NSUInteger inputType;
@property(nonatomic,assign) NSUInteger inputNumber;
@property(nonatomic,assign,getter=isAudioMuted) BOOL audioMuted;
@property(nonatomic,assign,getter=isVideoMuted) BOOL videoMuted;
@property(nonatomic,copy) NSArray* errorStatus;
@property(nonatomic,assign) NSUInteger fanError;
@property(nonatomic,assign) NSUInteger lampError;
@property(nonatomic,assign) NSUInteger temperatureError;
@property(nonatomic,assign) NSUInteger coverOpenError;
@property(nonatomic,assign) NSUInteger filterError;
@property(nonatomic,assign) NSUInteger otherError;
@property(nonatomic,assign) NSUInteger numberOfLamps;
@property(nonatomic,readonly) NSArray* lampStatus;
@property(nonatomic,copy) NSString* projectorName;
@property(nonatomic,copy) NSString* manufacturerName;
@property(nonatomic,copy) NSString* productName;
@property(nonatomic,copy) NSString* otherInformation;
@property(nonatomic,assign) BOOL class2Compatible;
@property(nonatomic,assign) BOOL usePassword;
@property(nonatomic,copy) NSString* password;

// KVC-compliant indexed accessor methods
- (NSUInteger)countOfInputInfo;
- (id)objectInInputInfoAtIndex:(NSUInteger)index;
- (NSUInteger)countOfErrorStatus;
- (id)objectInErrorStatusAtIndex:(NSUInteger)index;
- (NSUInteger)countOfLampStatus;
- (id)objectInLampStatusAtIndex:(NSUInteger)index;


- (void)handlePowerCommand:(BOOL)on;
- (void)handleInputSwitchWithType:(NSUInteger)type number:(NSUInteger)number;

@end
