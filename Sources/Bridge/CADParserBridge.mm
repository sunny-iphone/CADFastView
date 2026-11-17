#import "CADParserBridge.h"

#if USE_LIBDXFRW
#include "libdxfrw.h"
#include "libdwgr.h"
#include "drw_interface.h"
#include <string>
#include <vector>

class iOSDRWAdapter : public DRW_Interface {
public:
    NSMutableArray<CADBridgeLayer *> *layers = [NSMutableArray array];
    NSMutableArray<CADBridgeEntity *> *entities = [NSMutableArray array];

    void addLayer(const DRW_Layer &data) override {
        CADBridgeLayer *layer = [[CADBridgeLayer alloc] init];
        layer.name = [NSString stringWithUTF8String:data.name.c_str()] ?: @"0";
        layer.colorIndex = data.color;
        layer.visible = (data.flags & 0x01) == 0;
        [layers addObject:layer];
    }

    void addLine(const DRW_Line &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypeLine;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.coordinates = @[@(data.basePoint.x), @(data.basePoint.y), @(data.basePoint.z), @(data.secPoint.x), @(data.secPoint.y), @(data.secPoint.z)];
        [entities addObject:e];
    }

    void addLWPolyline(const DRW_LWPolyline &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypePolyline;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.closed = (data.flags & 0x01) != 0;
        NSMutableArray<NSNumber *> *coords = [NSMutableArray arrayWithCapacity:data.vertlist.size() * 2];
        for (const auto &v : data.vertlist) {
            [coords addObject:@(v->x)];
            [coords addObject:@(v->y)];
            [coords addObject:@(data.elevation)];
        }
        e.coordinates = coords;
        [entities addObject:e];
    }

    void addPolyline(const DRW_Polyline &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypePolyline;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.closed = (data.flags & 0x01) != 0;
        NSMutableArray<NSNumber *> *coords = [NSMutableArray arrayWithCapacity:data.vertlist.size() * 2];
        for (const auto &v : data.vertlist) {
            [coords addObject:@(v->basePoint.x)];
            [coords addObject:@(v->basePoint.y)];
            [coords addObject:@(v->basePoint.z)];
        }
        e.coordinates = coords;
        [entities addObject:e];
    }

    void addCircle(const DRW_Circle &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypeCircle;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.coordinates = @[@(data.basePoint.x), @(data.basePoint.y), @(data.basePoint.z)];
        e.radiusOrHeight = data.radious;
        [entities addObject:e];
    }

    void addArc(const DRW_Arc &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypeArc;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.coordinates = @[@(data.basePoint.x), @(data.basePoint.y), @(data.basePoint.z)];
        e.radiusOrHeight = data.radious;
        e.startAngleDeg = data.staangle * 180.0 / M_PI;
        e.endAngleDeg = data.endangle * 180.0 / M_PI;
        [entities addObject:e];
    }

    void addText(const DRW_Text &data) override {
        CADBridgeEntity *e = [[CADBridgeEntity alloc] init];
        e.type = CADBridgeEntityTypeText;
        e.layerName = [NSString stringWithUTF8String:data.layer.c_str()] ?: @"0";
        e.colorIndex = data.color;
        e.coordinates = @[@(data.basePoint.x), @(data.basePoint.y), @(data.basePoint.z)];
        e.radiusOrHeight = data.height;
        e.textContent = [NSString stringWithUTF8String:data.text.c_str()] ?: @"";
        [entities addObject:e];
    }

    // Unused DRW_Interface stubs required by libdxfrw
    void addHeader(const DRW_Header *) override {}
    void addLType(const DRW_LType &) override {}
    void addDimStyle(const DRW_Dimstyle &) override {}
    void addVport(const DRW_Vport &) override {}
    void addTextStyle(const DRW_Textstyle &) override {}
    void addAppId(const DRW_AppId &) override {}
    void addBlock(const DRW_Block &) override {}
    void setBlock(const int) override {}
    void endBlock() override {}
    void addPoint(const DRW_Point &) override {}
    void addRay(const DRW_Ray &) override {}
    void addXline(const DRW_Xline &) override {}
    void addEllipse(const DRW_Ellipse &) override {}
    void addSpline(const DRW_Spline *) override {}
    void addKnot(const DRW_Entity &) override {}
    void addInsert(const DRW_Insert &) override {}
    void addTrace(const DRW_Trace &) override {}
    void add3dFace(const DRW_3Dface &) override {}
    void addSolid(const DRW_Solid &) override {}
    void addMText(const DRW_MText &) override {}
    void addDimAlign(const DRW_DimAligned *) override {}
    void addDimLinear(const DRW_DimLinear *) override {}
    void addDimRadial(const DRW_DimRadial *) override {}
    void addDimDiametric(const DRW_DimDiametric *) override {}
    void addDimAngular(const DRW_DimAngular *) override {}
    void addDimAngular3P(const DRW_DimAngular3p *) override {}
    void addDimOrdinate(const DRW_DimOrdinate *) override {}
    void addLeader(const DRW_Leader *) override {}
    void addHatch(const DRW_Hatch *) override {}
    void addViewport(const DRW_Viewport &) override {}
    void addImage(const DRW_Image *) override {}
    void linkImage(const DRW_ImageDef *) override {}
    void addComment(const char *) override {}
    void writeHeader(DRW_Header &) override {}
    void writeBlocks() override {}
    void writeBlockRecords() override {}
    void writeEntities() override {}
    void writeLTypes() override {}
    void writeLayers() override {}
    void writeTextstyles() override {}
    void writeVports() override {}
    void writeDimstyles() override {}
    void writeAppId() override {}
};
#endif

@implementation CADBridgeLayer
@end

@implementation CADBridgeEntity
@end

@implementation CADBridgeResult
@end

@implementation CADParserBridge

+ (BOOL)isLibdxfrwAvailable {
#if USE_LIBDXFRW
    return YES;
#else
    return NO;
#endif
}

+ (CADBridgeResult *)parseFileAtPath:(NSString *)filePath {
    CADBridgeResult *result = [[CADBridgeResult alloc] init];
#if USE_LIBDXFRW
    iOSDRWAdapter adapter;
    std::string path([filePath UTF8String]);
    NSString *ext = [[filePath pathExtension] lowercaseString];
    bool ok = false;
    try {
        if ([ext isEqualToString:@"dwg"]) {
            dwgR dwg(path.c_str());
            ok = dwg.read(&adapter, false);
        } else {
            dxfRW dxf(path.c_str());
            ok = dxf.read(&adapter, false);
        }
    } catch (const std::exception &ex) {
        result.errorMessage = [NSString stringWithUTF8String:ex.what()] ?: @"C++ parser error.";
        return result;
    } catch (...) {
        result.errorMessage = @"Corrupted or unsupported CAD binary.";
        return result;
    }
    if (!ok) {
        result.errorMessage = @"libdxfrw failed to parse drawing.";
    }
    result.layers = adapter.layers;
    result.entities = adapter.entities;
#else
    result.errorMessage = @"libdxfrw is not enabled. Run scripts/fetch_libdxfrw.sh and set USE_LIBDXFRW=1.";
#endif
    return result;
}

@end
