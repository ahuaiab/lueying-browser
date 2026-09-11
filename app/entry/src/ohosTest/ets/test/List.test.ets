import browserGestureTest from './BrowserGesture.test';
import addressSecurityTest from './AddressSecurity.test';
import safariTabTransitionFeedbackTest from './SafariTabTransitionFeedback.test';

export default function testsuite() {
  browserGestureTest();
  addressSecurityTest();
  safariTabTransitionFeedbackTest();
}
