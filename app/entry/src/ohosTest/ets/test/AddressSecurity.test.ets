import { describe, expect, it } from '@ohos/hypium';
import {
  AddressSecurityState,
  addressBarLabelFor,
  addressSecurityStateFor
} from '../../../main/ets/browser/model/BrowserTypes';

export default function addressSecurityTest() {
  describe('AddressSecurity', () => {
    it('marks HTTPS pages as secure', 0, () => {
      expect(addressSecurityStateFor('https://example.com/path'))
        .assertEqual(AddressSecurityState.SECURE);
      expect(addressSecurityStateFor('HTTPS://EXAMPLE.COM'))
        .assertEqual(AddressSecurityState.SECURE);
    });

    it('marks HTTP and non-web pages as insecure', 0, () => {
      expect(addressSecurityStateFor('http://example.com'))
        .assertEqual(AddressSecurityState.INSECURE);
      expect(addressSecurityStateFor('about:blank'))
        .assertEqual(AddressSecurityState.INSECURE);
      expect(addressSecurityStateFor(''))
        .assertEqual(AddressSecurityState.INSECURE);
    });

    it('shows the search query and engine instead of a search URL', 0, () => {
      expect(addressBarLabelFor(
        'https://cn.bing.com/search?q=鸿蒙浏览器',
        '必应'
      )).assertEqual('鸿蒙浏览器-bing');
      expect(addressBarLabelFor(
        'https://login.live.com/oauth20_authorize.srf?redirect_uri=https%3A%2F%2Fcn.bing.com%2Fidentity%2Fidtokenv2',
        '鸿蒙浏览器-bing'
      )).assertEqual('鸿蒙浏览器-bing');
    });

    it('shows a page title instead of a direct page URL', 0, () => {
      expect(addressBarLabelFor('https://example.com/docs', 'Example Domain'))
        .assertEqual('Example Domain');
      expect(addressBarLabelFor('https://example.com/docs', ''))
        .assertEqual('网页');
    });
  });
}
