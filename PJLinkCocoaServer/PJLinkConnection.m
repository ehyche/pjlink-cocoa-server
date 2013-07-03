#import "GCDAsyncSocket.h"
#import "PJLinkServer.h"
#import "PJLinkConnection.h"
#import "PJLinkLogging.h"
#import "PJLinkConfig.h"
#import "PJProjector.h"
#import "PJInputInfo.h"
#import "PJLampStatus.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

// Log levels: off, error, warn, info, verbose
// Other flags: trace
static const int pjlinkLogLevel = PJ_LOG_LEVEL_WARN; // | PJ_LOG_FLAG_TRACE;

static NSArray* g_validCommands = nil;

// Define the various timeouts (in seconds) for various parts of the HTTP process
#define TIMEOUT_READ   30
#define TIMEOUT_WRITE  30

// Define the read and write tags
#define TAG_WRITE_AUTH_RESPONSE 10
#define TAG_WRITE_RESPONSE      11
#define TAG_READ_REQUEST        20

@interface PJLinkConnection()
{
	dispatch_queue_t _connectionQueue;
	GCDAsyncSocket*  _asyncSocket;
	PJLinkConfig*    _config;
	BOOL             _started;
}

- (void)die;
- (void)startConnection;
- (void)writeAuthResponse;
- (void)responseDataForRequestData:(NSData*)requestData withCompletion:(void (^)(NSData* responseData))block;

+ (NSData*)successResponseForRequest:(NSString*)request;
+ (NSData*)undefinedCommandResponseForRequest:(NSString*) request;
+ (NSData*)outOfParameterResponseForRequest:(NSString*) request;
+ (NSData*)unavailableTimeResponseForRequest:(NSString*) request;
+ (NSData*)projectorFailureResponseForRequest:(NSString*) request;
+ (BOOL)isValidCommand:(NSString*)command;

@end

@implementation PJLinkConnection

+ (void)initialize
{
    if (self == [PJLinkConnection class]) {
        g_validCommands = @[@"POWR", @"INPT", @"AVMT", @"ERST", @"LAMP", @"INST", @"NAME", @"INF1", @"INF2", @"INFO", @"CLSS"];
    }
}

- (id)initWithAsyncSocket:(GCDAsyncSocket *)newSocket configuration:(PJLinkConfig *)aConfig
{
    self = [super init];
    if (self)
    {
        PJLogTrace();
        
        if (aConfig.queue)
        {
            _connectionQueue = aConfig.queue;
#if !OS_OBJECT_USE_OBJC
            dispatch_retain(_connectionQueue);
#endif
        }
        else
        {
            _connectionQueue = dispatch_queue_create("PJLinkConnection", NULL);
        }
        
        // Take over ownership of the socket
        _asyncSocket = newSocket;
        [_asyncSocket setDelegate:self delegateQueue:_connectionQueue];
        
        // Store configuration
        _config = aConfig;
    }

    return self;
}

- (void)dealloc
{
    PJLogTrace();

#if !OS_OBJECT_USE_OBJC
    if (_connectionQueue != NULL) {
        dispatch_release(_connectionQueue);
        _connectionQueue = NULL;
    }
#endif

    [_asyncSocket setDelegate:nil delegateQueue:NULL];
    [_asyncSocket disconnect];
    _asyncSocket = nil;
}

- (void)start
{
	dispatch_async(_connectionQueue, ^{ @autoreleasepool {
		
		if (!_started)
		{
			_started = YES;
			[self startConnection];
		}
	}});
}

- (void)stop
{
	dispatch_async(_connectionQueue, ^{ @autoreleasepool {
		
		// Disconnect the socket.
		// The socketDidDisconnect delegate method will handle everything else.
		[_asyncSocket disconnect];
	}});
}

#pragma mark - GCDAsyncSocket delegate methods

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData*)data withTag:(long)tag
{
    if (tag == TAG_READ_REQUEST) {
        [self responseDataForRequestData:data withCompletion:^(NSData* responseData) {
            [_asyncSocket writeData:responseData
                        withTimeout:TIMEOUT_WRITE
                                tag:TAG_WRITE_RESPONSE];
        }];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if (tag == TAG_WRITE_AUTH_RESPONSE) {
        // Wait for the remote to send its first request
        [_asyncSocket readDataToData:[GCDAsyncSocket CRData]
                         withTimeout:TIMEOUT_READ
                                 tag:TAG_READ_REQUEST];
    } else if (tag == TAG_WRITE_RESPONSE) {
        // We wrote out the response to the request, now listen for more requests
        [_asyncSocket readDataToData:[GCDAsyncSocket CRData]
                         withTimeout:TIMEOUT_READ
                                 tag:TAG_READ_REQUEST];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    PJLogTrace();

    _asyncSocket = nil;

    [self die];
}

#pragma mark - PJLinkConnection private methods

- (void)die
{
    PJLogTrace();

    // Post notification of dead connection
    // This will allow our server to release us from its array of connections
    [[NSNotificationCenter defaultCenter] postNotificationName:PJLinkConnectionDidDieNotification object:self];
}

- (void)startConnection
{
    PJLogTrace();
    [self writeAuthResponse];
}

- (void)writeAuthResponse {
    NSString* noAuthResponse = @"PJLINK 0\r";
    NSData*   noAuthData     = [noAuthResponse dataUsingEncoding:NSUTF8StringEncoding];
    [_asyncSocket writeData:noAuthData
                withTimeout:TIMEOUT_WRITE
                        tag:TAG_WRITE_AUTH_RESPONSE];
}

- (void)responseDataForRequestData:(NSData*)requestData withCompletion:(void (^)(NSData* responseData))block {
    // Get the calling queue
    dispatch_queue_t curQueue = dispatch_get_current_queue();
    // Convert the data to a string using UTF8
    NSString* requestStr = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding];
    // Make sure we have at least 8 characters in the request
    NSData* errorResponseData = nil;
    if ([requestStr length] >= 8) {
        // Make sure the first two characters are "%1"
        if ([requestStr hasPrefix:@"%1"]) {
            // Get the command
            NSString* requestCommand = [requestStr substringWithRange:NSMakeRange(2, 4)];
            // Is this a valid command?
            if ([PJLinkConnection isValidCommand:requestCommand]) {
                // Is this a get or a set? If it's a get, then we will have " ?" following the command
                NSString* afterCommand = [requestStr substringWithRange:NSMakeRange(6, 2)];
                BOOL isGetCommand = [afterCommand isEqualToString:@" ?"];
                // Now dispatch over to the main queue to access the data model
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Get the projector
                    PJProjector* projector = [PJProjector sharedProjector];
                    // Is this a get?
                    NSString* responseStr = nil;
                    if (isGetCommand) {
                        // This is a get, so switch on command type
                        if ([requestCommand isEqualToString:@"POWR"]) {
                            responseStr = [NSString stringWithFormat:@"%%1POWR=%lu\r", (unsigned long)projector.powerStatus];
                        } else if ([requestCommand isEqualToString:@"INPT"]) {
                            responseStr = [NSString stringWithFormat:@"%%1INPT=%lu%lu\r", (unsigned long)projector.inputType, (unsigned long)projector.inputNumber];
                        } else if ([requestCommand isEqualToString:@"AVMT"]) {
                            NSString* muteStr = @"30";
                            if (projector.isAudioMuted) {
                                if (projector.isVideoMuted) {
                                    muteStr = @"31";
                                } else {
                                    muteStr = @"21";
                                }
                            } else if (projector.isVideoMuted) {
                                muteStr = @"11";
                            }
                            responseStr = [NSString stringWithFormat:@"%%1AVMT=%@\r", muteStr];
                        } else if ([requestCommand isEqualToString:@"ERST"]) {
                            responseStr = [NSString stringWithFormat:@"%%1ERST=%lu%lu%lu%lu%lu%lu\r",
                                           (unsigned long)projector.fanError, (unsigned long)projector.lampError,
                                           (unsigned long)projector.temperatureError, (unsigned long)projector.coverOpenError,
                                           (unsigned long)projector.filterError, (unsigned long)projector.otherError];
                        } else if ([requestCommand isEqualToString:@"LAMP"]) {
                            NSMutableString* lampStr = [NSMutableString string];
                            NSArray* lampStatuses = projector.lampStatus;
                            for (PJLampStatus* lampStatus in lampStatuses) {
                                if ([lampStr length] > 0) {
                                    [lampStr appendString:@" "];
                                }
                                [lampStr appendFormat:@"%lu %u", (unsigned long)lampStatus.cumulativeLightingHours, lampStatus.isOn];
                            }
                            responseStr = [NSString stringWithFormat:@"%%1LAMP=%@\r", lampStr];
                        } else if ([requestCommand isEqualToString:@"INST"]) {
                            NSMutableString* inputStr = [NSMutableString string];
                            NSArray* inputInfo = projector.inputInfo;
                            NSUInteger numInputTypes = [inputInfo count];
                            for (NSUInteger i = 0; i < numInputTypes; i++) {
                                PJInputInfo* ithInputInfo = [inputInfo objectAtIndex:i];
                                for (NSUInteger j = 0; j < ithInputInfo.numberOfInputs; j++) {
                                    if ([inputStr length] > 0) {
                                        [inputStr appendString:@" "];
                                    }
                                    [inputStr appendFormat:@"%lu%lu", (unsigned long) (i + 1), (unsigned long) (j + 1)];
                                }
                            }
                            responseStr = [NSString stringWithFormat:@"%%1INST=%@\r", inputStr];
                        } else if ([requestCommand isEqualToString:@"NAME"]) {
                            responseStr = [NSString stringWithFormat:@"%%1NAME=%@\r", projector.projectorName];
                        } else if ([requestCommand isEqualToString:@"INF1"]) {
                            responseStr = [NSString stringWithFormat:@"%%1INF1=%@\r", projector.manufacturerName];
                        } else if ([requestCommand isEqualToString:@"INF2"]) {
                            responseStr = [NSString stringWithFormat:@"%%1INF2=%@\r", projector.productName];
                        } else if ([requestCommand isEqualToString:@"INFO"]) {
                            responseStr = [NSString stringWithFormat:@"%%1INFO=%@\r", projector.otherInformation];
                        } else if ([requestCommand isEqualToString:@"CLSS"]) {
                            responseStr = [NSString stringWithFormat:@"%%1CLSS=%u\r", (projector.class2Compatible ? 2 : 1)];
                        } else {
                            // Send an undefined command
                            responseStr = [NSString stringWithFormat:@"%@=ERR1\r", [requestStr substringToIndex:6]];
                        }
                    } else {
                        // This is a set, so switch on command type
                        if ([requestCommand isEqualToString:@"POWR"]) {
                            NSString* powerControlStr = [requestStr substringWithRange:NSMakeRange(7, 1)];
                            NSUInteger powerControl = [powerControlStr integerValue];
                            if (powerControl <= 1) {
                                BOOL powerOn = (powerControl == 1 ? YES : NO);
                                // Tell the projector to change power state.
                                [projector handlePowerCommand:powerOn];
                                // Sucessful response
                                responseStr = @"%1POWR=OK\r";
                            } else {
                                // Invalid power command - bad parameter error
                                responseStr = @"%1POWR=ERR2\r";
                            }
                        } else if ([requestCommand isEqualToString:@"INPT"]) {
                            NSString* inputTypeStr = [requestStr substringWithRange:NSMakeRange(7, 1)];
                            NSString* inputNumStr  = [requestStr substringWithRange:NSMakeRange(8, 1)];
                            NSUInteger inputType = [inputTypeStr integerValue];
                            NSUInteger inputNum  = [inputNumStr integerValue];
                            if (inputType >= 1 && inputType <= 5) {
                                if (inputNum < 1) {
                                    // Invalid input number
                                    responseStr = @"%1INPT=ERR2\r";
                                } else {
                                    BOOL validInputNum = YES;
                                    NSUInteger inputInfoIndex = inputType - 1;
                                    PJInputInfo* ithInputInfo = [projector.inputInfo objectAtIndex:inputInfoIndex];
                                    if (inputNum > ithInputInfo.numberOfInputs) {
                                        validInputNum = NO;
                                    }
                                    if (validInputNum) {
                                        // Switch the project input type and number at the same time
                                        [projector handleInputSwitchWithType:inputType number:inputNum];
                                        // Successful response
                                        responseStr = @"%1INPT=OK\r";
                                    } else {
                                        responseStr = @"%1INPT=ERR2\r";
                                    }
                                }
                            } else {
                                // Invalid input type
                                responseStr = @"%1INPT=ERR2\r";
                            }
                        } else if ([requestCommand isEqualToString:@"AVMT"]) {
                            // Get the mute parameters
                            NSString*  muteChannelStr = [requestStr substringWithRange:NSMakeRange(7, 1)];
                            NSString*  muteStateStr   = [requestStr substringWithRange:NSMakeRange(8, 1)];
                            NSUInteger muteChannel    = [muteChannelStr integerValue];
                            NSUInteger muteState      = [muteStateStr integerValue];
                            if (muteState < 2) {
                                BOOL muteOn = (muteState == 1 ? YES : NO);
                                if (muteChannel == 1) {
                                    projector.videoMuted = muteOn;
                                    responseStr = @"%1AVMT=OK\r";
                                } else if (muteChannel == 2) {
                                    projector.audioMuted = muteOn;
                                    responseStr = @"%1AVMT=OK\r";
                                } else if (muteChannel == 3) {
                                    projector.videoMuted = muteOn;
                                    projector.audioMuted = muteOn;
                                    responseStr = @"%1AVMT=OK\r";
                                } else {
                                    // Invalid parameter
                                    responseStr = @"%1AVMT=ERR2\r";
                                }
                            } else {
                                // Invalid parameter
                                responseStr = @"%1AVMT=ERR2\r";
                            }
                        } else {
                            // Send an undefined command
                            responseStr = [NSString stringWithFormat:@"%@=ERR1\r", [requestStr substringToIndex:6]];
                        }
                    }
                    // Create the response data
                    NSData* responseData = [responseStr dataUsingEncoding:NSUTF8StringEncoding];
                    // Dispatch back to the calling queue
                    dispatch_async(curQueue, ^{
                        block(responseData);
                    });
                });
            } else {
                // Malformed request - invalid command
                errorResponseData = [PJLinkConnection undefinedCommandResponseForRequest:requestStr];
            }
        } else {
            // Malformed request - no proper prefix and class
            errorResponseData = [PJLinkConnection undefinedCommandResponseForRequest:requestStr];
        }
    } else {
        // Malformed request - not long enough, so create an error response with a made-up command
        errorResponseData = [PJLinkConnection undefinedCommandResponseForRequest:@"%1POWR"];
    }
    // Do we have an error response?
    if (errorResponseData != nil) {
        // Dispatch back to the calling queue
        dispatch_async(curQueue, ^{
            block(errorResponseData);
        });
    }
}

+ (NSData*)successResponseForRequest:(NSString*)request {
    NSString* responseStr = [NSString stringWithFormat:@"%@=OK\r", [request substringToIndex:6]];
    return [responseStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData*)undefinedCommandResponseForRequest:(NSString*) request {
    NSString* responseStr = [NSString stringWithFormat:@"%@=ERR1\r", [request substringToIndex:6]];
    return [responseStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData*)outOfParameterResponseForRequest:(NSString*) request {
    NSString* responseStr = [NSString stringWithFormat:@"%@=ERR2\r", [request substringToIndex:6]];
    return [responseStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData*)unavailableTimeResponseForRequest:(NSString*) request {
    NSString* responseStr = [NSString stringWithFormat:@"%@=ERR3\r", [request substringToIndex:6]];
    return [responseStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData*)projectorFailureResponseForRequest:(NSString*) request {
    NSString* responseStr = [NSString stringWithFormat:@"%@=ERR4\r", [request substringToIndex:6]];
    return [responseStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (BOOL)isValidCommand:(NSString*)command {
    BOOL ret = NO;

    if ([command length] > 0) {
        ret = [g_validCommands containsObject:command];
    }

    return ret;
}

@end

