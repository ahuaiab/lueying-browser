import browserGestureTest from './BrowserGesture.test';
import addressSecurityTest from './AddressSecurity.test';

export default function testsuite() {
  browserGestureTest();
  addressSecurityTest();
}
