#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CADBridgeEntityType) {
    CADBridgeEntityTypeLine = 0,
    CADBridgeEntityTypePolyline = 1,
    CADBridgeEntityTypeCircle = 2,
    CADBridgeEntityTypeArc = 3,
    CADBridgeEntityTypeText = 4
};

@interface CADBridgeLayer : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger colorIndex;
@property (nonatomic, assign) BOOL visible;
@end

@interface CADBridgeEntity : NSObject
@property (nonatomic, assign) CADBridgeEntityType type;
@property (nonatomic, copy) NSString *layerName;
@property (nonatomic, assign) NSInteger colorIndex;
/// Flat interleaved [x0, y0, x1, y1, ...] for lines/polylines, or [cx, cy] for circle/arc/text.
@property (nonatomic, strong) NSArray<NSNumber *> *coordinates;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, assign) double radiusOrHeight;
@property (nonatomic, assign) double startAngleDeg;
@property (nonatomic, assign) double endAngleDeg;
@property (nonatomic, copy, nullable) NSString *textContent;
@end

@interface CADBridgeResult : NSObject
@property (nonatomic, strong) NSArray<CADBridgeLayer *> *layers;
@property (nonatomic, strong) NSArray<CADBridgeEntity *> *entities;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

@interface CADParserBridge : NSObject
+ (BOOL)isLibdxfrwAvailable;
+ (CADBridgeResult *)parseFileAtPath:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
