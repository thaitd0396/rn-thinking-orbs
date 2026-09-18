# rn-thinking-orbs

Native React Native view that draws a striped dotted thinking orb with Core Graphics (iOS) and `android.graphics.Canvas` (Android). No Skia.

```tsx
import {ThinkingOrbsView} from 'rn-thinking-orbs';

<ThinkingOrbsView
  accentColor="#2A67F4"
  dotColor="#000000"
  animated
  style={{width: 120, height: 120}}
/>
```

Keep the native view at a fixed size (for example 120pt) and scale the wrapper in JS if the layout slot shrinks. Do not change the native canvas size during keyboard or layout animation.

Autolinks on iOS and Android. After adding the package, rebuild the native app (`pod install` / Gradle). CodePush cannot ship the native view.

Native hosts such as `habitify-ios-mac` and `habitify-android` pick the view up the next time they integrate this React Native workspace. No extra host-only ViewManager is required.

## Props

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `accentColor` | `string` | `#2A67F4` | Hex for highlight dots |
| `dotColor` | `string` | `#000000` | Hex for the rest of the field |
| `animated` | `boolean` | `true` | Drive the loop; `false` draws frame 0 |
