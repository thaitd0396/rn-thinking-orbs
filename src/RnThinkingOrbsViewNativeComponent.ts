import {codegenNativeComponent, type ViewProps} from 'react-native';
import type {WithDefault} from 'react-native/Libraries/Types/CodegenTypes';

export interface NativeProps extends ViewProps {
  accentColor?: string;
  dotColor?: string;
  animated?: WithDefault<boolean, true>;
  interactive?: WithDefault<boolean, false>;
}

export default codegenNativeComponent<NativeProps>('RnThinkingOrbsView');
