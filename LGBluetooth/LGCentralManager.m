// The MIT License (MIT)
//
// Created by : l0gg3r
// Copyright (c) 2014 SocialObjects Software. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "LGCentralManager.h"

#if TARGET_OS_IPHONE
#import <CoreBluetooth/CoreBluetooth.h>
#elif TARGET_OS_MAC
#import <IOBluetooth/IOBluetooth.h>
#endif
#import "LGPeripheral.h"
#import "LGUtils.h"

@interface LGCentralManager() <CBCentralManagerDelegate>

/**
 * Ongoing operations
 */
@property (strong, atomic) NSMutableDictionary *operations;

/**
 * CBCentralManager's dispatch queue
 */
@property (strong, nonatomic) dispatch_queue_t centralQueue;

/**
 * List of scanned peripherals
 */
@property (strong, nonatomic) NSMutableArray *scannedPeripherals;

/**
 * Completion block for peripheral scanning
 */
@property (copy, nonatomic) LGCentralManagerDiscoverPeripheralsCallback scanBlock;

/**
 * CBCentralManager's state updated by centralManagerDidUpdateState:
 */
@property(nonatomic) CBCentralManagerState cbCentralManagerState;

@end

@implementation LGCentralManager

/*----------------------------------------------------*/
#pragma mark - Getter/Setter -
/*----------------------------------------------------*/

- (BOOL)isCentralReady
{
    return (self.manager.state == CBCentralManagerStatePoweredOn);
}

- (NSString *)centralNotReadyReason
{
    return [self stateMessage];
}

- (NSArray *)peripherals
{
    // Sorting LGPeripherals by RSSI values
    NSArray *sortedArray;
    sortedArray = [_scannedPeripherals sortedArrayUsingComparator:^NSComparisonResult(LGPeripheral *a, LGPeripheral *b) {
        return a.RSSI==0 || a.RSSI < b.RSSI;
    }];
    return sortedArray;
}

/*----------------------------------------------------*/
#pragma mark - KVO -
/*----------------------------------------------------*/

+ (NSSet *)keyPathsForValuesAffectingCentralReady
{
    return [NSSet setWithObject:@"cbCentralManagerState"];
}

+ (NSSet *)keyPathsForValuesAffectingCentralNotReadyReason
{
    return [NSSet setWithObject:@"cbCentralManagerState"];
}

/*----------------------------------------------------*/
#pragma mark - Public Methods -
/*----------------------------------------------------*/

- (void)scanForPeripherals
{
    [self scanForPeripheralsWithServices:nil
                                 options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @YES}];
}

- (void)stopScanForPeripherals
{
    self.scanning = NO;
	[self.manager stopScan];
    if (self.scanBlock) {
        self.scanBlock(self.peripherals);
        self.scanBlock = nil;
    }
}

- (void)scanForPeripheralsWithServices:(NSArray *)serviceUUIDs
                               options:(NSDictionary *)options
{
    NSArray* pcopy = [self.scannedPeripherals copy];
    [self.scannedPeripherals removeAllObjects];
    // Don't remove connected peripherals.  They will not appear in a scan
    for(LGPeripheral* p in pcopy) {
        switch( p.cbPeripheral.state ) {
            case CBPeripheralStateConnected:
            case CBPeripheralStateConnecting:
                [self.scannedPeripherals addObject:p];
                break;
            default:
                break;
        }
    }
    
    self.scanning = YES;
	[self.manager scanForPeripheralsWithServices:serviceUUIDs
                                         options:options];
}

- (void)scanForPeripheralsByInterval:(NSUInteger)aScanInterval
                          completion:(LGCentralManagerDiscoverPeripheralsCallback)aCallback
{
    [self scanForPeripheralsByInterval:aScanInterval
                              services:nil
                               options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @YES}
                            completion:aCallback];
}

- (void)scanForPeripheralsByInterval:(NSUInteger)aScanInterval
                            services:(NSArray *)serviceUUIDs
                             options:(NSDictionary *)options
                          completion:(LGCentralManagerDiscoverPeripheralsCallback)aCallback
{
    self.scanBlock = aCallback;
    NSLog(@"SCAN");
    [self scanForPeripheralsWithServices:serviceUUIDs
                                 options:options];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,aScanInterval*NSEC_PER_SEC),self.callbackQueue,^{
        [self stopScanForPeripherals];
    });
}

- (NSArray *)retrievePeripheralsWithIdentifiers:(NSArray *)identifiers
{
    return [self wrappersByPeripherals:[self.manager retrievePeripheralsWithIdentifiers:identifiers]];
}

- (NSArray *)retrieveConnectedPeripheralsWithServices:(NSArray *)serviceUUIDS
{
    return [self wrappersByPeripherals:[self.manager retrieveConnectedPeripheralsWithServices:serviceUUIDS]];
}

/*----------------------------------------------------*/
#pragma mark - Private Methods -
/*----------------------------------------------------*/

- (NSString *)stateMessage
{
	NSString *message = nil;
	switch (self.manager.state) {
		case CBCentralManagerStateUnsupported:
			message = @"The platform/hardware doesn't support Bluetooth Low Energy.";
			break;
		case CBCentralManagerStateUnauthorized:
			message = @"The app is not authorized to use Bluetooth Low Energy.";
			break;
        case CBCentralManagerStateUnknown:
            message = @"Central not initialized yet.";
            break;
		case CBCentralManagerStatePoweredOff:
			message = @"Bluetooth is currently powered off.";
			break;
		case CBCentralManagerStatePoweredOn:
            break;
		default:
			break;
	}
	return message;
}

- (LGPeripheral *)wrapperByPeripheral:(CBPeripheral *)aPeripheral
{
    LGPeripheral *wrapper = nil;
    for (LGPeripheral *scanned in self.scannedPeripherals) {
        if (scanned.cbPeripheral == aPeripheral) {
            wrapper = scanned;
            break;
        }
    }
    if (!wrapper) {
        wrapper = [[LGPeripheral alloc] initWithPeripheral:aPeripheral manager:self];
        [self.scannedPeripherals addObject:wrapper];
    }
    return wrapper;
}

- (NSArray *)wrappersByPeripherals:(NSArray *)peripherals
{
    NSMutableArray *lgPeripherals = [NSMutableArray new];
    
    for (CBPeripheral *peripheral in peripherals) {
        [lgPeripherals addObject:[self wrapperByPeripheral:peripheral]];
    }
    return lgPeripherals;
}

//-------------------------------------------------------------------------//
#pragma mark - Central Manager Delegate
//-------------------------------------------------------------------------//

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    dispatch_async(LG_DISPATCH_QUEUE, ^{
        [[self wrapperByPeripheral:peripheral] handleConnectionWithError:nil];
    });
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
    dispatch_async(LG_DISPATCH_QUEUE, ^{
        [[self wrapperByPeripheral:peripheral] handleConnectionWithError:error];
    });
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error
{
    dispatch_async(LG_DISPATCH_QUEUE, ^{
        LGPeripheral *lgPeripheral = [self wrapperByPeripheral:peripheral];
        [lgPeripheral handleDisconnectWithError:error];
    });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    self.cbCentralManagerState = central.state;
    NSString *message = [self stateMessage];
    if (message) {
        dispatch_async(LG_DISPATCH_QUEUE, ^{
            LGLogError(@"%@", message);
        });
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    dispatch_async(LG_DISPATCH_QUEUE, ^{
        LGPeripheral *lgPeripheral = [self wrapperByPeripheral:peripheral];
        // Average RSSI data over time and ignore 127 values
        if([RSSI integerValue] != 127) {
            if (!lgPeripheral.RSSI ) {
                lgPeripheral.RSSI = [RSSI integerValue];
            } else {
                lgPeripheral.RSSI = (lgPeripheral.RSSI + [RSSI integerValue]) / 2;
            }
        }
        lgPeripheral.advertisingData = advertisementData;
        
        if ([self.scannedPeripherals count] >= self.peripheralsCountToStop) {
            [self stopScanForPeripherals];
        }
    });
}

/*----------------------------------------------------*/
#pragma mark - LifeCycle -
/*----------------------------------------------------*/

static LGCentralManager *sharedInstance = nil;

+ (LGCentralManager *)sharedInstance
{
    // Thread blocking to be sure for singleton instance
	@synchronized(self) {
		if (!sharedInstance) {
			sharedInstance = [LGCentralManager new];
		}
	}
	return sharedInstance;
}

- (id)init
{
	self = [super init];
	if (self) {
        _callbackQueue= dispatch_queue_create("com.LGBluetooth.LGCallbackQueue", DISPATCH_QUEUE_SERIAL);
        _centralQueue = dispatch_queue_create("com.LGBluetooth.LGCentralQueue",  DISPATCH_QUEUE_SERIAL);
        _manager      = [[CBCentralManager alloc] initWithDelegate:self queue:self.centralQueue];
        _cbCentralManagerState = _manager.state;
        _scannedPeripherals = [NSMutableArray new];
        _peripheralsCountToStop = NSUIntegerMax;
	}
	return self;
}

@end
