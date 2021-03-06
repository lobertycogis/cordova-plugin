#import "IndoorLocation.h"
#pragma mark IndoorLocationInfo

@implementation IndoorLocationInfo

- (IndoorLocationInfo *)init
{
    self = (IndoorLocationInfo *)[super init];
    if (self) {
        self.locationInfo = nil;
        self.locationCallbacks = nil;
        self.watchCallbacks = nil;
    }
    return self;
}

@end

#pragma mark -

#pragma mark IndoorLocationInfo

@implementation IndoorRegionInfo

- (IndoorRegionInfo *)init
{
    self = (IndoorRegionInfo *)[super init];
    if (self) {
        self.region = nil;
        self.regionStatus = TRANSITION_TYPE_UNKNOWN;
        self.watchCallbacks = nil;
    }
    return self;
}

@end

#pragma mark -

#pragma mark IndoorLocation
@interface IndoorLocation ()<IALocationDelegate> {
}

@property (nonatomic, strong) IndoorAtlasLocationService *IAlocationInfo;
@property (nonatomic, strong) NSString *floorPlanCallbackID;
@property (nonatomic, strong) NSString *coordinateToPointCallbackID;
@property (nonatomic, strong) NSString *pointToCoordinateCallbackID;
@property (nonatomic, strong) NSString *setDistanceFilterCallbackID;
@property (nonatomic, strong) NSString *getFloorCertaintyCallbackID;
@property (nonatomic, strong) NSString *getTraceIdCallbackID;
@property (nonatomic, strong) NSString *addAttitudeUpdateCallbackID;
@property (nonatomic, strong) NSString *addHeadingUpdateCallbackID;
@property (nonatomic, strong) NSString *addStatusUpdateCallbackID;

@end

@implementation IndoorLocation
{
    BOOL __locationStarted;
}


- (void)pluginInitialize
{
    self.locationManager = [[CLLocationManager alloc] init];
    __locationStarted = NO;
    self.locationData = nil;
    self.regionData = nil;
}

- (BOOL)isAuthorized
{
    BOOL authorizationStatusClassPropertyAvailable = [CLLocationManager respondsToSelector:@selector(authorizationStatus)]; // iOS 4.2+

    if (authorizationStatusClassPropertyAvailable) {
        NSUInteger authStatus = [CLLocationManager authorizationStatus];
#ifdef __IPHONE_8_0
        if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {  //iOS 8.0+
            return (authStatus == kCLAuthorizationStatusAuthorizedWhenInUse) || (authStatus == kCLAuthorizationStatusAuthorizedAlways) || (authStatus == kCLAuthorizationStatusNotDetermined);
        }
#else
        return (authStatus == kCLAuthorizationStatusAuthorized) || (authStatus == kCLAuthorizationStatusNotDetermined);
#endif

    }

    // by default, assume YES (for iOS < 4.2)
    return YES;
}

- (BOOL)isLocationServicesEnabled
{
    BOOL locationServicesEnabledInstancePropertyAvailable = [self.locationManager respondsToSelector:@selector(locationServicesEnabled)]; // iOS 3.x
    BOOL locationServicesEnabledClassPropertyAvailable = [CLLocationManager respondsToSelector:@selector(locationServicesEnabled)]; // iOS 4.x

    if (locationServicesEnabledClassPropertyAvailable) { // iOS 4.x
        return [CLLocationManager locationServicesEnabled];
    } else if (locationServicesEnabledInstancePropertyAvailable) { // iOS 2.x, iOS 3.x
        return [(id)self.locationManager locationServicesEnabled];

    } else {
        return NO;
    }
}

- (void)startLocation
{
    if (![self isLocationServicesEnabled]) {
        [self returnLocationError:PERMISSION_DENIED withMessage:@"Location services are not enabled."];
        return;
    }
    if (![self isAuthorized]) {
        NSString *message = nil;
        BOOL authStatusAvailable = [CLLocationManager respondsToSelector:@selector(authorizationStatus)]; // iOS 4.2+
        if (authStatusAvailable) {
            NSUInteger code = [CLLocationManager authorizationStatus];
            if (code == kCLAuthorizationStatusNotDetermined) {
                // could return POSITION_UNAVAILABLE but need to coordinate with other platforms
                message = @"User undecided on application's use of location services.";
            } else if (code == kCLAuthorizationStatusRestricted) {
                message = @"Application's use of location services is restricted.";
            }
            else if(code == kCLAuthorizationStatusDenied) {
                message = @"Application's use of location services is restricted.";
            }
        }
        // PERMISSIONDENIED is only PositionError that makes sense when authorization denied
        [self returnLocationError:PERMISSION_DENIED withMessage:message];

        return;
    }

#ifdef __IPHONE_8_0
    NSUInteger code = [CLLocationManager authorizationStatus];
    if (code == kCLAuthorizationStatusNotDetermined && ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)] || [self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)])) { //iOS8+
        if([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"]) {
            [self.locationManager requestWhenInUseAuthorization];
        } else if([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationAlwaysUsageDescription"]) {
            [self.locationManager requestAlwaysAuthorization];
        } else {
            NSLog(@"[Warning] No NSLocationAlwaysUsageDescription or NSLocationWhenInUseUsageDescription key is defined in the Info.plist file.");
        }
        return;
    }
#endif

    __locationStarted = YES;
    [self.IAlocationInfo startPositioning];
}

- (void)_stopLocation
{
    BOOL stopLocationservice = YES;

    if(self.locationData && (self.locationData.watchCallbacks.count > 0 ||self.locationData.locationCallbacks.count > 0)) {
        stopLocationservice = NO;
    }
    else if(self.regionData && self.regionData.watchCallbacks.count > 0) {
        stopLocationservice = NO;
    }
    if (stopLocationservice) {
        if (__locationStarted) {
            if (![self isLocationServicesEnabled]) {
                return;
            }

            [self.locationManager stopUpdatingLocation];
            __locationStarted = NO;
        }
        [self.IAlocationInfo stopPositioning];
    }
}

- (void)returnLocationInfo:(NSString *)callbackId andKeepCallback:(BOOL)keepCallback
{
    CDVPluginResult *result = nil;
    IndoorLocationInfo *lData = self.locationData;

    if (lData && !lData.locationInfo) {
        // return error
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:POSITION_UNAVAILABLE] forKey:@"code"];
        [posError setObject:@"Position not available" forKey:@"message"];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
    } else if (lData && lData.locationInfo) {
        CLLocation *lInfo = lData.locationInfo;
        NSMutableDictionary *returnInfo = [NSMutableDictionary dictionaryWithCapacity:10];
        NSNumber *timestamp = [NSNumber numberWithDouble:([lInfo.timestamp timeIntervalSince1970] * 1000)];
        [returnInfo setObject:timestamp forKey:@"timestamp"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.speed] forKey:@"velocity"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.verticalAccuracy] forKey:@"altitudeAccuracy"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.horizontalAccuracy] forKey:@"accuracy"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.course] forKey:@"heading"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.altitude] forKey:@"altitude"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.coordinate.latitude] forKey:@"latitude"];
        [returnInfo setObject:[NSNumber numberWithDouble:lInfo.coordinate.longitude] forKey:@"longitude"];

        [returnInfo setObject:lData.floorID forKey:@"flr"];
        [returnInfo setObject:lData.floorCertainty forKey:@"floorCertainty"];
        if (lData.region != nil) {
            [returnInfo setObject:[self formatRegionInfo:lData.region andTransitionType:TRANSITION_TYPE_UNKNOWN] forKey:@"region"];
        }

        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnInfo];
        [result setKeepCallbackAsBool:keepCallback];
    }
    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (void)returnRegionInfo:(NSString *)callbackId andKeepCallback:(BOOL)keepCallback
{
    CDVPluginResult *result = nil;
    IndoorRegionInfo *lData = self.regionData;

    if (lData && !lData.region) {
        // return error
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:POSITION_UNAVAILABLE] forKey:@"code"];
        [posError setObject:@"Region not available" forKey:@"message"];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
    } else if (lData && lData.region) {
        NSMutableDictionary *returnInfo = [NSMutableDictionary dictionaryWithDictionary:[self formatRegionInfo:lData.region andTransitionType:lData.regionStatus]];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnInfo];
        [result setKeepCallbackAsBool:keepCallback];
    }
    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (void)returnLocationError:(NSUInteger)errorCode withMessage:(NSString *)message
{
    NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];

    [posError setObject:[NSNumber numberWithUnsignedInteger:errorCode] forKey:@"code"];
    [posError setObject:message ? message:@"" forKey:@"message"];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];

    for (NSString *callbackId in self.locationData.locationCallbacks) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }

    [self.locationData.locationCallbacks removeAllObjects];

    for (NSString *callbackId in self.locationData.watchCallbacks) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (void)returnAttitudeInformation:(double)x y:(double)y z:(double)z w:(double)w timestamp:(NSDate *)timestamp
{
    if (_addAttitudeUpdateCallbackID != nil) {
        CDVPluginResult *pluginResult;
        
        NSNumber *secondsSinceRefDate = [NSNumber numberWithDouble:[timestamp timeIntervalSinceReferenceDate]];
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:5];
        [result setObject:secondsSinceRefDate forKey:@"timestamp"];
        [result setObject:[NSNumber numberWithDouble:x] forKey:@"x"];
        [result setObject:[NSNumber numberWithDouble:y] forKey:@"y"];
        [result setObject:[NSNumber numberWithDouble:z] forKey:@"z"];
        [result setObject:[NSNumber numberWithDouble:w] forKey:@"w"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.addAttitudeUpdateCallbackID];
    }
}

- (void)returnHeadingInformation:(double)heading timestamp:(NSDate *)timestamp
{
    if (_addHeadingUpdateCallbackID != nil) {
        CDVPluginResult *pluginResult;
        
        NSNumber *secondsSinceRefDate = [NSNumber numberWithDouble:[timestamp timeIntervalSinceReferenceDate]];
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
        [result setObject:secondsSinceRefDate forKey:@"timestamp"];
        [result setObject:[NSNumber numberWithDouble:heading] forKey:@"trueHeading"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.addHeadingUpdateCallbackID];
    }
}

- (void)returnStatusInformation:(NSString *)statusString code:(NSUInteger) code
{
    if (_addStatusUpdateCallbackID != nil) {
        CDVPluginResult *pluginResult;
        
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
        [result setObject:statusString forKey:@"message"];
        [result setObject:[NSNumber numberWithUnsignedInteger:code] forKey:@"code"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.addStatusUpdateCallbackID];
    }
}

- (NSDictionary *)formatRegionInfo:(IARegion *)regionInfo andTransitionType:(IndoorLocationTransitionType)transitionType
{
    NSMutableDictionary *result;
    result = [[NSMutableDictionary alloc] init];
    [result setObject:regionInfo.identifier forKey:@"regionId"];
    NSNumber *timestamp = [NSNumber numberWithDouble:([regionInfo.timestamp timeIntervalSince1970] * 1000)];
    [result setObject:timestamp forKey:@"timestamp"];
    [result setObject:[NSNumber numberWithInt:regionInfo.type] forKey:@"regionType"];
    [result setObject:[NSNumber numberWithInteger:transitionType] forKey:@"transitionType"];
    return result;
}
- (void)dealloc
{
    self.locationManager.delegate = nil;
}

- (void)onReset
{
    [self _stopLocation];
    [self.locationManager stopUpdatingHeading];
}


#pragma mark Expose Methods implementation

- (void)initializeIndoorAtlas:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    CDVPluginResult *pluginResult;
    NSDictionary *options = [command.arguments objectAtIndex:0];

    NSString *iakey = [options objectForKey:@"key"];
    NSString *iasecret = [options objectForKey:@"secret"];
    if (iakey == nil || iasecret == nil) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
        [result setObject:[NSNumber numberWithInt:INVALID_ACCESS_TOKEN] forKey:@"code"];
        [result setObject:@"Invalid access token" forKey:@"message"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
    else {
        self.IAlocationInfo = [[IndoorAtlasLocationService alloc] init:iakey hash:iasecret];
        self.IAlocationInfo.delegate = self;

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
        [result setObject:[NSNumber numberWithInt:0] forKey:@"code"];
        [result setObject:@"service Initialize" forKey:@"message"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }

}

- (void)setPosition:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;

    if (self.IAlocationInfo == nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:INVALID_ACCESS_TOKEN] forKey:@"code"];
        [posError setObject:@"Invalid access token" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];

    }
    else {
        NSString *region = [command.arguments objectAtIndex:0];
        NSArray *location = [command.arguments objectAtIndex:1];
        NSString *floorPlanId = [command.arguments objectAtIndex:2];
        NSString *venueId = [command.arguments objectAtIndex:3];

        CLLocation *newLocation = nil;
        if([location count] == 2) {
            newLocation = [[CLLocation alloc] initWithLatitude:[location[0] doubleValue] longitude:[location[1] doubleValue]];
        }

        if (floorPlanId != nil && ![floorPlanId isEqualToString:@""]) {
            [self.IAlocationInfo setFloorPlan:floorPlanId];

        } else if (region != nil && ![region isEqualToString:@""]) {
            [self.IAlocationInfo setFloorPlan:region];

        } else if (venueId != nil && ![venueId isEqualToString:@""]) {
            [self.IAlocationInfo setVenue: venueId];

        }

        if (location != nil) {
            [self.IAlocationInfo setLocation: newLocation];
        }

        CDVPluginResult *pluginResult;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
        [result setObject:[NSNumber numberWithInt:0] forKey:@"code"];
        [result setObject:@"service Initialize" forKey:@"message"];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
}

- (void)getLocation:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    if (self.IAlocationInfo == nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:INVALID_ACCESS_TOKEN] forKey:@"code"];
        [posError setObject:@"Invalid access token" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }

    if ([self isLocationServicesEnabled] == NO) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:PERMISSION_DENIED] forKey:@"code"];
        [posError setObject:@"Location services are disabled." forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    } else {
        if (!self.locationData) {
            self.locationData = [[IndoorLocationInfo alloc] init];
        }
        IndoorLocationInfo *lData = self.locationData;
        if (!lData.locationCallbacks) {
            lData.locationCallbacks = [NSMutableArray arrayWithCapacity:1];
        }

        if (!__locationStarted || _locationData.region == nil) {
            // add the callbackId into the array so we can call back when get data
            if (callbackId != nil) {
                [lData.locationCallbacks addObject:callbackId];
            }

            // Tell the location manager to start notifying us of heading updates
            [self startLocation];
        } else {
            [self returnLocationInfo:callbackId andKeepCallback:NO];
        }
    }
}

- (void)addWatch:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    if (self.IAlocationInfo == nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:INVALID_ACCESS_TOKEN] forKey:@"code"];
        [posError setObject:@"Invalid access token" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }
    NSString *timerId = [command argumentAtIndex:0];

    if (!self.locationData) {
        self.locationData = [[IndoorLocationInfo alloc] init];
    }
    IndoorLocationInfo *lData = self.locationData;

    if (!lData.watchCallbacks) {
        lData.watchCallbacks = [NSMutableDictionary dictionaryWithCapacity:1];
    }

    // add the callbackId into the dictionary so we can call back whenever get data
    [lData.watchCallbacks setObject:callbackId forKey:timerId];

    if ([self isLocationServicesEnabled] == NO) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:PERMISSION_DENIED] forKey:@"code"];
        [posError setObject:@"Location services are disabled." forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    } else {
        if (!__locationStarted) {
            // Tell the location manager to start notifying us of location updates
            [self startLocation];
        }
    }
}

- (void)clearWatch:(CDVInvokedUrlCommand *)command
{
    NSString *timerId = [command argumentAtIndex:0];

    if (self.locationData && self.locationData.watchCallbacks && [self.locationData.watchCallbacks objectForKey:timerId]) {
        [self.locationData.watchCallbacks removeObjectForKey:timerId];
        if([self.locationData.watchCallbacks count] == 0) {
            [self _stopLocation];
        }
    }
}

- (void)addRegionWatch:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    if (self.IAlocationInfo == nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:INVALID_ACCESS_TOKEN] forKey:@"code"];
        [posError setObject:@"Invalid access token" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        return;
    }
    NSString *timerId = [command argumentAtIndex:0];

    if (!self.regionData) {
        self.regionData = [[IndoorRegionInfo alloc] init];
    }
    IndoorRegionInfo *lData = self.regionData;

    if (!lData.watchCallbacks) {
        lData.watchCallbacks = [NSMutableDictionary dictionaryWithCapacity:1];
    }

    // add the callbackId into the dictionary so we can call back whenever get data
    [lData.watchCallbacks setObject:callbackId forKey:timerId];

    if ([self isLocationServicesEnabled] == NO) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithInt:PERMISSION_DENIED] forKey:@"code"];
        [posError setObject:@"Location services are disabled." forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    } else {
        if (!__locationStarted) {
            // Tell the location manager to start notifying us of location updates
            [self startLocation];
        }
    }
}

- (void)clearRegionWatch:(CDVInvokedUrlCommand *)command
{
    NSString *timerId = [command argumentAtIndex:0];

    if (self.regionData && self.regionData.watchCallbacks && [self.regionData.watchCallbacks objectForKey:timerId]) {
        [self.regionData.watchCallbacks removeObjectForKey:timerId];
        if([self.regionData.watchCallbacks count] == 0) {
            [self _stopLocation];
        }
    }
}

- (void)addAttitudeCallback:(CDVInvokedUrlCommand *)command
{
    _addAttitudeUpdateCallbackID = command.callbackId;
}

- (void)removeAttitudeCallback:(CDVInvokedUrlCommand *)command
{
    _addAttitudeUpdateCallbackID = nil;
}

- (void)addHeadingCallback:(CDVInvokedUrlCommand *)command
{
    _addHeadingUpdateCallbackID = command.callbackId;
}

- (void)removeHeadingCallback:(CDVInvokedUrlCommand *)command
{
    _addHeadingUpdateCallbackID = nil;
}

- (void)addStatusChangedCallback:(CDVInvokedUrlCommand *)command
{
    _addStatusUpdateCallbackID = command.callbackId;
}

- (void)removeStatusCallback:(CDVInvokedUrlCommand *)command
{
    _addStatusUpdateCallbackID = nil;
}

- (void)stopLocation:(CDVInvokedUrlCommand *)command
{
    [self _stopLocation];
}

- (void)fetchFloorplan:(CDVInvokedUrlCommand *)command
{
    [self.IAlocationInfo fetchFloorplanWithId:[command argumentAtIndex:0] callbackId: command.callbackId];
}

// DEPRECATED
// CoordinateToPoint Method
// Gets the arguments from the function call that is done in the Javascript side, then calls IALocationService's getCoordinateToPoint function
- (void)coordinateToPoint:(CDVInvokedUrlCommand *)command
{
    // Callback id of the call from Javascript side
    self.coordinateToPointCallbackID = command.callbackId;

    NSString *floorplanid = [command argumentAtIndex:2];
    NSString *latitude = [command argumentAtIndex:0];
    NSString *longitude = [command argumentAtIndex:1];

    CLLocationCoordinate2D coords = CLLocationCoordinate2DMake([latitude doubleValue], [longitude doubleValue]);
    NSLog(@"coordinateToPoint: latitude %f", coords.latitude);
    NSLog(@"coordinateToPoint: longitude %f", coords.longitude);

    [self.IAlocationInfo getCoordinateToPoint:floorplanid andCoordinates:coords];
}

// DEPRECATED
// Prepares the result for Cordova plugin and Javascript side. Point is stored in dictionary which is then passed to Javascript side with the Cordova functions
- (void)sendCoordinateToPoint:(CGPoint) point
{
    NSLog(@"sendCoordinateToPoint: point %@", NSStringFromCGPoint(point));

    NSMutableDictionary *returnInfo = [NSMutableDictionary dictionaryWithCapacity:2];
    [returnInfo setObject:[NSNumber numberWithDouble:point.x] forKey:@"x"];
    [returnInfo setObject:[NSNumber numberWithDouble:point.y] forKey:@"y"];

    // Cordova plugin functions
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnInfo];
    [self.commandDelegate sendPluginResult:result callbackId:self.coordinateToPointCallbackID];
}

// DEPRECATED
// PointToCoordinate Method
// Gets the arguments from the function call that is done in the Javascript side, then calls IALocationService's getPointToCoordinate function
- (void)pointToCoordinate:(CDVInvokedUrlCommand *)command
{
    // Callback id of the call from Javascript side
    self.pointToCoordinateCallbackID = command.callbackId;

    NSString *floorplanid = [command argumentAtIndex:2];
    NSString *x = [command argumentAtIndex:0];
    NSString *y = [command argumentAtIndex:1];

    NSLog(@"pointToCoordinate: x %@", x);
    NSLog(@"pointToCoordinate: y %@", y);

    CGPoint point = CGPointMake([x floatValue], [y floatValue]);

    [self.IAlocationInfo getPointToCoordinate:floorplanid andPoint:point];
}

// DEPRECATED
// Prepares the result for Cordova plugin and Javascript side. Point is stored in dictionary which is then passed to Javascript side with the Cordova functions
- (void)sendPointToCoordinate:(CLLocationCoordinate2D)coords
{
    NSLog(@"sendPointToCoordinate: latitude %f", coords.latitude);
    NSLog(@"sendPointToCoordinate: longitude %f", coords.longitude);

    NSMutableDictionary *returnInfo = [NSMutableDictionary dictionaryWithCapacity:2];
    [returnInfo setObject:[NSNumber numberWithDouble:coords.latitude] forKey:@"latitude"];
    [returnInfo setObject:[NSNumber numberWithDouble:coords.longitude] forKey:@"longitude"];

    // Cordova plugin functions
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnInfo];
    [self.commandDelegate sendPluginResult:result callbackId:self.pointToCoordinateCallbackID];
}

- (void)setDistanceFilter:(CDVInvokedUrlCommand *)command
{
    self.setDistanceFilterCallbackID = command.callbackId;
    NSString *distance = [command argumentAtIndex:0];

    float d = [distance floatValue];
    [self.IAlocationInfo valueForDistanceFilter: &d];

    CDVPluginResult *pluginResult;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
    [result setObject:@"DistanceFilter set" forKey:@"message"];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.setDistanceFilterCallbackID];
}

- (void)getFloorCertainty:(CDVInvokedUrlCommand *)command
{
  self.getFloorCertaintyCallbackID = command.callbackId;
  float certainty = [self.IAlocationInfo fetchFloorCertainty];

  CDVPluginResult *pluginResult;
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
  [result setObject:[NSNumber numberWithFloat:certainty] forKey:@"floorCertainty"];

  pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:self.getFloorCertaintyCallbackID];
}

- (void)getTraceId:(CDVInvokedUrlCommand *)command
{
  self.getTraceIdCallbackID = command.callbackId;
  NSString *traceId = [self.IAlocationInfo fetchTraceId];

  CDVPluginResult *pluginResult;
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
  [result setObject:traceId forKey:@"traceId"];

  pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:self.getTraceIdCallbackID];
}

- (void)setSensitivities:(CDVInvokedUrlCommand *)command
{
    NSString *oSensitivity = [command argumentAtIndex:0];
    NSString *hSensitivity = [command argumentAtIndex:1];
    
    double orientationSensitivity = [oSensitivity doubleValue];
    double headingSensitivity = [hSensitivity doubleValue];
    
    [self.IAlocationInfo setSensitivities: &orientationSensitivity headingSensitivity:&headingSensitivity];
    
    CDVPluginResult *pluginResult;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
    [result setObject:@"Sensitivities set" forKey:@"message"];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/**
 * Initialize the graph with the given graph JSON
 */
- (void)buildWayfinder:(CDVInvokedUrlCommand *)command
{
    NSString *graphJson = [command argumentAtIndex:0];
    
    if (self.wayfinderInstances == nil) {
        self.wayfinderInstances = [[NSMutableArray alloc] init];
    }
    
    int wayfinderId = [self.wayfinderInstances count];
    
    @try {
        IAWayfinding *wf = [[IAWayfinding alloc] initWithGraph:graphJson];
        [self.wayfinderInstances addObject:wf];
    } @catch(NSException *exception) {
        NSLog(@"graph: %@", exception.reason);
        [self sendErrorCommand:command withMessage:@"Error: graph"];
    }
    
    CDVPluginResult *pluginResult;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
    [result setObject: [NSNumber numberWithInteger:wayfinderId] forKey:@"wayfinderId"];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
    
}

/**
 * Compute route for the given values;
 * 1) Set location of the wayfinder instance
 * 2) Set destination of the wayfinder instance
 * 3) Get route between the given location and destination
 */
- (void)computeRoute:(CDVInvokedUrlCommand *)command
{
    NSString *wayfinderId = [command argumentAtIndex:0];
    NSString *lat0 = [command argumentAtIndex:1];
    NSString *lon0 = [command argumentAtIndex:2];
    NSString *floor0 = [command argumentAtIndex:3];
    NSString *lat1 = [command argumentAtIndex:4];
    NSString *lon1 = [command argumentAtIndex:5];
    NSString *floor1 = [command argumentAtIndex:6];
    
    self.wayfinder = self.wayfinderInstances[[wayfinderId intValue]];
    
    @try {
        [self.wayfinder setLocationWithLatitude:[lat0 doubleValue] Longitude:[lon0 doubleValue] Floor:[floor0 intValue]];
    } @catch(NSException *exception) {
        NSLog(@"loc: %@", exception.reason);
        [self sendErrorCommand:command withMessage:@"Error: loc"];
    }
    
    @try {
        [self.wayfinder setDestinationWithLatitude:[lat1 doubleValue] Longitude:[lon1 doubleValue] Floor:[floor1 intValue]];
    } @catch(NSException *exception) {
        NSLog(@"dest: %@", exception.reason);
        [self sendErrorCommand:command withMessage:@"Error: dest"];
    }
    
    CDVPluginResult *pluginResult;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:1];
    NSArray<IARoutingLeg *> *route = [NSArray array];
    
    @try {
        route = [self.wayfinder getRoute];
    } @catch(NSException *exception) {
        NSLog(@"route: %@", exception.reason);
    }
    
    NSMutableArray<NSMutableDictionary *>* routingLegs = [[NSMutableArray alloc] init];
    for (int i=0; i < [route count]; i++) {
        [routingLegs addObject:[self dictionaryFromRoutingLeg:route[i]]];
    }
    
    [result setObject:routingLegs forKey:@"route"];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
}

/**
 * Create NSMutableDictionary from the RoutingLeg object
 */
- (NSMutableDictionary *)dictionaryFromRoutingLeg:(IARoutingLeg *)routingLeg {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys: [self dictionaryFromRoutingPoint:routingLeg.begin], @"begin", [self dictionaryFromRoutingPoint:routingLeg.end], @"end", [NSNumber numberWithDouble:routingLeg.length], @"length", [NSNumber numberWithDouble:routingLeg.direction], @"direction", routingLeg.edgeIndex, @"edgeIndex", nil];
}

/**
 * Create NSMutableDictionary from the RoutingPoint object
 */
- (NSMutableDictionary *)dictionaryFromRoutingPoint:(IARoutingPoint *)routingPoint {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:routingPoint.latitude], @"latitude", [NSNumber numberWithDouble:routingPoint.longitude], @"longitude", [NSNumber numberWithInt:routingPoint.floor], @"floor", routingPoint.nodeIndex, @"nodeIndex", nil];
}

/**
 * Send error command back to JavaScript side
 */
- (void)sendErrorCommand:(CDVInvokedUrlCommand *)command withMessage:(NSString *)message
{
    CDVPluginResult *pluginResult;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark IndoorAtlas Location
- (void)location:(IndoorAtlasLocationService *)manager didUpdateLocation:(IALocation *)newLocation
{
    IndoorLocationInfo *cData = self.locationData;

    cData.locationInfo = [[CLLocation alloc] initWithCoordinate:newLocation.location.coordinate altitude:0 horizontalAccuracy:newLocation.location.horizontalAccuracy verticalAccuracy:0 course:newLocation.location.course speed:0 timestamp:[NSDate date]];
    cData.floorID = [NSString stringWithFormat:@"%ld", newLocation.floor.level];
    cData.floorCertainty = [NSNumber numberWithFloat:newLocation.floor.certainty];
    cData.region = newLocation.region;
    if (self.locationData.locationCallbacks.count > 0) {
        for (NSString *callbackId in self.locationData.locationCallbacks) {
            [self returnLocationInfo:callbackId andKeepCallback:NO];
        }

        [self.locationData.locationCallbacks removeAllObjects];
    }
    if (self.locationData.watchCallbacks.count > 0) {
        for (NSString *timerId in self.locationData.watchCallbacks) {
            [self returnLocationInfo:[self.locationData.watchCallbacks objectForKey:timerId] andKeepCallback:YES];
        }
    } else {
        // No callbacks waiting on us anymore, turn off listening.
        [self _stopLocation];
    }
}

- (void)location:(IndoorAtlasLocationService *)manager didFailWithError:(NSError *)error
{
    NSLog(@"locationManager::didFailWithError %@", [error localizedFailureReason]);
    IndoorLocationInfo *lData = self.locationData;
    if (lData && __locationStarted) {
        // TODO: probably have to once over the various error codes and return one of:
        // PositionError.PERMISSION_DENIED = 1;
        // PositionError.POSITION_UNAVAILABLE = 2;
        // PositionError.TIMEOUT = 3;
        NSUInteger positionError = POSITION_UNAVAILABLE;
        [self returnLocationError:positionError withMessage:[error localizedDescription]];
    }
}

- (void)location:(IndoorAtlasLocationService *)manager didRegionChange:(IARegion *)region type:(IndoorLocationTransitionType)enterOrExit
{
    if (region == nil) {
        return;
    }
    IndoorRegionInfo *cData = self.regionData;
    cData.region = region;
    cData.regionStatus = enterOrExit;
    if (self.regionData.watchCallbacks.count > 0) {
        for (NSString *timerId in self.regionData.watchCallbacks) {
            [self returnRegionInfo:[self.regionData.watchCallbacks objectForKey:timerId] andKeepCallback:YES];
        }
    } else {
        // No callbacks waiting on us anymore, turn off listening.
        [self _stopLocation];
    }
}

- (void)location:(IndoorAtlasLocationService *)manager didUpdateAttitude:(IAAttitude *)attitude
{
    double x = attitude.quaternion.x;
    double y = attitude.quaternion.y;
    double z = attitude.quaternion.z;
    double w = attitude.quaternion.w;
    NSDate *timestamp = attitude.timestamp;
    
    [self returnAttitudeInformation:x y:y z:z w:w timestamp:timestamp];
}

- (void)location:(IndoorAtlasLocationService *)manager didUpdateHeading:(IAHeading *)heading
{
    double direction = heading.trueHeading;
    NSDate *timestamp = heading.timestamp;
    
    [self returnHeadingInformation:direction timestamp:timestamp];
}

- (void)location:(IndoorAtlasLocationService *)manager statusChanged:(IAStatus *)status
{
    NSString *statusDisplay;
    NSUInteger statusCode;
    switch (status.type) {
        case kIAStatusServiceAvailable:
            statusDisplay = @"Available";
            statusCode = STATUS_AVAILABLE;
            break;
        case kIAStatusServiceOutOfService:
            statusDisplay = @"Out of Service";
            statusCode = STATUS_OUT_OF_SERVICE;
            break;
        case kIAStatusServiceUnavailable:
            statusDisplay = @"Service Unavailable";
            statusCode = STATUS_TEMPORARILY_UNAVAILABLE;
            break;
        case kIAStatusServiceLimited:
            statusDisplay = @"Service Limited";
            statusCode = STATUS_LIMITED;
            break;
        default:
            statusDisplay = @"Unspecified Status";
            break;
    }
    
    [self returnStatusInformation:statusDisplay code:statusCode];
    NSLog(@"IALocationManager status %d %@", status.type, statusDisplay) ;
}

- (void)location:(IndoorAtlasLocationService *)manager withFloorPlan:(IAFloorPlan *)floorPlan callbackId:(NSString *)callbackId
{
    if (callbackId != nil) {

        NSMutableDictionary *returnInfo = [NSMutableDictionary dictionaryWithCapacity:17];

        NSNumber *timestamp = [NSNumber numberWithDouble:([[NSDate date] timeIntervalSince1970] * 1000)];
        [returnInfo setObject:timestamp forKey:@"timestamp"];
        [returnInfo setObject:floorPlan.floorPlanId forKey:@"id"];
        [returnInfo setObject:floorPlan.name forKey:@"name"];
        [returnInfo setObject:[floorPlan.imageUrl absoluteString] forKey:@"url"];
        [returnInfo setObject:[NSNumber numberWithInteger:floorPlan.floor.level] forKey:@"floorLevel"];
        [returnInfo setObject:[NSNumber numberWithDouble: floorPlan.bearing] forKey:@"bearing"];
        [returnInfo setObject:[NSNumber numberWithInteger:floorPlan.height] forKey:@"bitmapHeight"];
        [returnInfo setObject:[NSNumber numberWithInteger:floorPlan.width] forKey:@"bitmapWidth"];
        [returnInfo setObject:[NSNumber numberWithFloat:floorPlan.heightMeters] forKey:@"heightMeters"];
        [returnInfo setObject:[NSNumber numberWithFloat:floorPlan.widthMeters] forKey:@"widthMeters"];
        [returnInfo setObject:[NSNumber numberWithFloat:floorPlan.meterToPixelConversion] forKey:@"metersToPixels"];
        [returnInfo setObject:[NSNumber numberWithFloat:floorPlan.pixelToMeterConversion] forKey:@"pixelsToMeters"];
        CLLocationCoordinate2D locationPoint = floorPlan.bottomLeft;
        [returnInfo setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:locationPoint.longitude], [NSNumber numberWithDouble:locationPoint.latitude], nil] forKey:@"bottomLeft"];
        locationPoint = floorPlan.center;
        [returnInfo setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:locationPoint.longitude], [NSNumber numberWithDouble:locationPoint.latitude], nil] forKey:@"center"];
        locationPoint = floorPlan.topLeft;
        [returnInfo setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:locationPoint.longitude], [NSNumber numberWithDouble:locationPoint.latitude], nil] forKey:@"topLeft"];
        locationPoint = floorPlan.topRight;
        [returnInfo setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:locationPoint.longitude], [NSNumber numberWithDouble:locationPoint.latitude], nil] forKey:@"topRight"];

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnInfo];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (void)location:(IndoorAtlasLocationService *)manager didFloorPlanFailedWithError:(NSError *)error
{
    NSLog(@"locationManager::didFloorPlanFailedWithError %@", [error localizedFailureReason]);
    if (self.floorPlanCallbackID != nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithUnsignedInteger:FLOORPLAN_UNAVAILABLE] forKey:@"code"];
        [posError setObject:[error localizedDescription] ? [error localizedDescription]:@"" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];

        [self.commandDelegate sendPluginResult:result callbackId:self.floorPlanCallbackID];
    }
}

- (void)errorInCoordinateToPoint:(NSError *) error
{
    NSLog(@"locationManager::didFloorPlanFailedWithError %@", [error localizedFailureReason]);
    if (self.coordinateToPointCallbackID != nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithUnsignedInteger:FLOORPLAN_UNAVAILABLE] forKey:@"code"];
        [posError setObject:[error localizedDescription] ? [error localizedDescription]:@"" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];

        [self.commandDelegate sendPluginResult:result callbackId:self.coordinateToPointCallbackID];
    }
}
- (void)errorInPointToCoordinate:(NSError *) error
{
    NSLog(@"locationManager::didFloorPlanFailedWithError %@", [error localizedFailureReason]);
    if (self.pointToCoordinateCallbackID != nil) {
        NSMutableDictionary *posError = [NSMutableDictionary dictionaryWithCapacity:2];
        [posError setObject:[NSNumber numberWithUnsignedInteger:FLOORPLAN_UNAVAILABLE] forKey:@"code"];
        [posError setObject:[error localizedDescription] ? [error localizedDescription]:@"" forKey:@"message"];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:posError];

        [self.commandDelegate sendPluginResult:result callbackId:self.pointToCoordinateCallbackID];
    }
}
@end
