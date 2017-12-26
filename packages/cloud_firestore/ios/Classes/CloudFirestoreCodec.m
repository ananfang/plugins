// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
//  CloudFirestoreCodec.m
//  cloud_firestore
//
//  Created by ananfang on 26/12/2017.
//  ananfang@gmail.com
//

#import "CloudFirestoreCodec.h"

#pragma mark - 
@implementation FlutterStandardMessageCodec
+ (instancetype)sharedInstance {
    static id _sharedInstance = nil;
    if (!_sharedInstance) {
        _sharedInstance = [FlutterStandardMessageCodec new];
    }
    return _sharedInstance;
}

- (NSData*)encode:(id)message {
    if (message == nil)
        return nil;
    NSMutableData* data = [NSMutableData dataWithCapacity:32];
    FlutterStandardWriter* writer = [FlutterStandardWriter writerWithData:data];
    [writer writeValue:message];
    return data;
}

- (id)decode:(NSData*)message {
    if (message == nil)
        return nil;
    FlutterStandardReader* reader = [FlutterStandardReader readerWithData:message];
    id value = [reader readValue];
    NSAssert(![reader hasMore], @"Corrupted standard message");
    return value;
}
@end

#pragma mark - CloudFirestoreCodecHelper
@implementation CloudFirestoreCodecHelper
+ (CloudFirestoreField)cloudFirestoreFieldForDataType:(FlutterStandardDataType)type {
    return (CloudFirestoreField)(type + CloudFirestoreFieldUInt8Data);
}

+ (FlutterStandardDataType)flutterStandardDataTypeForField:(CloudFirestoreField)field {
    return (FlutterStandardDataType)(field - CloudFirestoreFieldUInt8Data);
}

+ (UInt8)elementSizeForFlutterStandardDataType:(FlutterStandardDataType)type {
    switch (type) {
        case FlutterStandardDataTypeUInt8:
            return 1;
        case FlutterStandardDataTypeInt32:
            return 4;
        case FlutterStandardDataTypeInt64:
            return 8;
        case FlutterStandardDataTypeFloat64:
            return 8;
    }
}

+ (FlutterStandardTypedData *)typedDataWithData:(NSData *)data type:(FlutterStandardDataType)type {
    switch (type) {
        case FlutterStandardDataTypeUInt8:
            return [FlutterStandardTypedData typedDataWithBytes:data];
        case FlutterStandardDataTypeInt32:
            return [FlutterStandardTypedData typedDataWithInt32:data];
        case FlutterStandardDataTypeInt64:
            return [FlutterStandardTypedData typedDataWithInt64:data];
        case FlutterStandardDataTypeFloat64:
            return [FlutterStandardTypedData typedDataWithFloat64:data];
    }
}
@end

#pragma mark - CloudFirestoreWriter
@implementation CloudFirestoreWriter {
    NSMutableData* _data;
}

+ (instancetype)writerWithData:(NSMutableData*)data {
    return [[CloudFirestoreWriter alloc] initWithData:data];
}

- (instancetype)initWithData:(NSMutableData*)data {
    self = [super init];
    NSAssert(self, @"Super init cannot be nil");
    _data = data;
    return self;
}

- (void)writeByte:(UInt8)value {
    [_data appendBytes:&value length:1];
}

- (void)writeSize:(UInt32)size {
    if (size < 254) {
        [self writeByte:(UInt8)size];
    } else if (size <= 0xffff) {
        [self writeByte:254];
        UInt16 value = (UInt16)size;
        [_data appendBytes:&value length:2];
    } else {
        [self writeByte:255];
        [_data appendBytes:&size length:4];
    }
}

- (void)writeAlignment:(UInt8)alignment {
    UInt8 mod = _data.length % alignment;
    if (mod) {
        for (int i = 0; i < (alignment - mod); i++) {
            [self writeByte:0];
        }
    }
}

- (void)writeUTF8:(NSString*)value {
    UInt32 length = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    [self writeSize:length];
    [_data appendBytes:value.UTF8String length:length];
}

- (void)writeValue:(id)value {
    if (value == nil || value == [NSNull null]) {
        [self writeByte:CloudFirestoreFieldNil];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber* number = value;
        const char* type = [number objCType];
        if ([self isBool:number type:type]) {
            BOOL b = number.boolValue;
            [self writeByte:(b ? CloudFirestoreFieldTrue : CloudFirestoreFieldFalse)];
        } else if (strcmp(type, @encode(signed int)) == 0 || strcmp(type, @encode(signed short)) == 0 ||
                   strcmp(type, @encode(unsigned short)) == 0 ||
                   strcmp(type, @encode(signed char)) == 0 ||
                   strcmp(type, @encode(unsigned char)) == 0) {
            SInt32 n = number.intValue;
            [self writeByte:CloudFirestoreFieldInt32];
            [_data appendBytes:(UInt8*)&n length:4];
        } else if (strcmp(type, @encode(signed long)) == 0 ||
                   strcmp(type, @encode(unsigned int)) == 0) {
            SInt64 n = number.longValue;
            [self writeByte:CloudFirestoreFieldInt64];
            [_data appendBytes:(UInt8*)&n length:8];
        } else if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
            Float64 f = number.doubleValue;
            [self writeByte:CloudFirestoreFieldFloat64];
            [self writeAlignment:8];
            [_data appendBytes:(UInt8*)&f length:8];
        } else if (strcmp(type, @encode(unsigned long)) == 0 ||
                   strcmp(type, @encode(signed long long)) == 0 ||
                   strcmp(type, @encode(unsigned long long)) == 0) {
            NSString* hex = [NSString stringWithFormat:@"%llx", number.unsignedLongLongValue];
            [self writeByte:CloudFirestoreFieldIntHex];
            [self writeUTF8:hex];
        } else {
            NSLog(@"Unsupported value: %@ of type %s", value, type);
            NSAssert(NO, @"Unsupported value for Firebase/Cloud Firestore codec");
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        NSString* string = value;
        [self writeByte:CloudFirestoreFieldString];
        [self writeUTF8:string];
    } else if ([value isKindOfClass:[FlutterStandardBigInteger class]]) {
        FlutterStandardBigInteger* bigInt = value;
        [self writeByte:CloudFirestoreFieldIntHex];
        [self writeUTF8:bigInt.hex];
    } else if ([value isKindOfClass:[FlutterStandardTypedData class]]) {
        FlutterStandardTypedData* typedData = value;
        [self writeByte:[CloudFirestoreCodecHelper cloudFirestoreFieldForDataType:typedData.type]];
        [self writeSize:typedData.elementCount];
        [self writeAlignment:typedData.elementSize];
        [_data appendData:typedData.data];
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray* array = value;
        [self writeByte:CloudFirestoreFieldList];
        [self writeSize:array.count];
        for (id object in array) {
            [self writeValue:object];
        }
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dict = value;
        [self writeByte:CloudFirestoreFieldMap];
        [self writeSize:dict.count];
        for (id key in dict) {
            [self writeValue:key];
            [self writeValue:[dict objectForKey:key]];
        }
    } else {
        NSLog(@"Unsupported value: %@ of type %@", value, [value class]);
        NSAssert(NO, @"Unsupported value for Firebase/Cloud Firestore codec");
    }
}

- (BOOL)isBool:(NSNumber*)number type:(const char*)type {
    return strcmp(type, @encode(signed char)) == 0 &&
    [NSStringFromClass([number class]) isEqual:@"__NSCFBoolean"];
}
@end

#pragma mark - CloudFirestoreReader
@implementation CloudFirestoreReader {
    NSData* _data;
    NSRange _range;
}

+ (instancetype)readerWithData:(NSData*)data {
    return [[CloudFirestoreReader alloc] initWithData:data];
}

- (instancetype)initWithData:(NSData*)data {
    self = [super init];
    NSAssert(self, @"Super init cannot be nil");
    _data = data;
    _range = NSMakeRange(0, 0);
    return self;
}

- (BOOL)hasMore {
    return _range.location < _data.length;
}

- (void)readBytes:(void*)destination length:(int)length {
    _range.length = length;
    [_data getBytes:destination range:_range];
    _range.location += _range.length;
}

- (UInt8)readByte {
    UInt8 value;
    [self readBytes:&value length:1];
    return value;
}

- (UInt32)readSize {
    UInt8 byte = [self readByte];
    if (byte < 254) {
        return (UInt32)byte;
    } else if (byte == 254) {
        UInt16 value;
        [self readBytes:&value length:2];
        return value;
    } else {
        UInt32 value;
        [self readBytes:&value length:4];
        return value;
    }
}

- (NSData*)readData:(int)length {
    _range.length = length;
    NSData* data = [_data subdataWithRange:_range];
    _range.location += _range.length;
    return data;
}

- (NSString*)readUTF8 {
    NSData* bytes = [self readData:[self readSize]];
    return [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
}

- (void)readAlignment:(UInt8)alignment {
    UInt8 mod = _range.location % alignment;
    if (mod) {
        _range.location += (alignment - mod);
    }
}

- (FlutterStandardTypedData*)readTypedDataOfType:(FlutterStandardDataType)type {
    UInt32 elementCount = [self readSize];
    UInt8 elementSize = [CloudFirestoreCodecHelper elementSizeForFlutterStandardDataType:type];
    [self readAlignment:elementSize];
    NSData* data = [self readData:elementCount * elementSize];
    return [CloudFirestoreCodecHelper typedDataWithData:data type:type];
}

- (id)readValue {
    CloudFirestoreField field = (CloudFirestoreField)[self readByte];
    switch (field) {
        case CloudFirestoreFieldNil:
            return nil;
        case CloudFirestoreFieldTrue:
            return @YES;
        case CloudFirestoreFieldFalse:
            return @NO;
        case CloudFirestoreFieldInt32: {
            SInt32 value;
            [self readBytes:&value length:4];
            return [NSNumber numberWithInt:value];
        }
        case CloudFirestoreFieldInt64: {
            SInt64 value;
            [self readBytes:&value length:8];
            return [NSNumber numberWithLong:value];
        }
        case CloudFirestoreFieldFloat64: {
            Float64 value;
            [self readAlignment:8];
            [self readBytes:&value length:8];
            return [NSNumber numberWithDouble:value];
        }
        case CloudFirestoreFieldIntHex:
            return [FlutterStandardBigInteger bigIntegerWithHex:[self readUTF8]];
        case CloudFirestoreFieldString:
            return [self readUTF8];
        case CloudFirestoreFieldUInt8Data:
        case CloudFirestoreFieldInt32Data:
        case CloudFirestoreFieldInt64Data:
        case CloudFirestoreFieldFloat64Data:
            return [self readTypedDataOfType:[CloudFirestoreCodecHelper flutterStandardDataTypeForField:field]];
        case CloudFirestoreFieldList: {
            UInt32 length = [self readSize];
            NSMutableArray* array = [NSMutableArray arrayWithCapacity:length];
            for (UInt32 i = 0; i < length; i++) {
                id value = [self readValue];
                [array addObject:(value == nil ? [NSNull null] : value)];
            }
            return array;
        }
        case CloudFirestoreFieldMap: {
            UInt32 size = [self readSize];
            NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:size];
            for (UInt32 i = 0; i < size; i++) {
                id key = [self readValue];
                id val = [self readValue];
                [dict setObject:(val == nil ? [NSNull null] : val)
                         forKey:(key == nil ? [NSNull null] : key)];
            }
            return dict;
        }
        default:
            NSAssert(NO, @"Corrupted standard message");
    }
}
@end
