#import "RnThinkingOrbsView.h"

#import <react/renderer/components/RnThinkingOrbsSpec/ComponentDescriptors.h>
#import <react/renderer/components/RnThinkingOrbsSpec/EventEmitters.h>
#import <react/renderer/components/RnThinkingOrbsSpec/Props.h>
#import <react/renderer/components/RnThinkingOrbsSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

using namespace facebook::react;

@interface RnThinkingOrbsView () <RCTRnThinkingOrbsViewViewProtocol>
@end

@implementation RnThinkingOrbsView {
  UIView *_orbsView;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RnThinkingOrbsViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const RnThinkingOrbsViewProps>();
    _props = defaultProps;
    Class cls = NSClassFromString(@"ThinkingOrbsUIView");
    _orbsView = [[cls alloc] initWithFrame:self.bounds];
    _orbsView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _orbsView.backgroundColor = UIColor.clearColor;
    self.contentView = _orbsView;
  }
  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<RnThinkingOrbsViewProps const>(_props);
  const auto &newViewProps = *std::static_pointer_cast<RnThinkingOrbsViewProps const>(props);

  if (oldViewProps.accentColor != newViewProps.accentColor) {
    NSString *value = [NSString stringWithUTF8String:newViewProps.accentColor.c_str()];
    [_orbsView setValue:value forKey:@"accentColor"];
  }
  if (oldViewProps.dotColor != newViewProps.dotColor) {
    NSString *value = [NSString stringWithUTF8String:newViewProps.dotColor.c_str()];
    [_orbsView setValue:value forKey:@"dotColor"];
  }
  if (oldViewProps.animated != newViewProps.animated) {
    [_orbsView setValue:@(newViewProps.animated) forKey:@"animated"];
  }
  if (oldViewProps.interactive != newViewProps.interactive) {
    [_orbsView setValue:@(newViewProps.interactive) forKey:@"interactive"];
  }

  [super updateProps:props oldProps:oldProps];
}

Class<RCTComponentViewProtocol> RnThinkingOrbsViewCls(void)
{
  return RnThinkingOrbsView.class;
}

@end
