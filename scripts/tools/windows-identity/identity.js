// The --user-agent flag doesn't change these, and pages can read them too.
Object.defineProperty(navigator, 'platform', {get: () => 'Win32'});
if (navigator.userAgentData) {
  const brands = navigator.userAgentData.brands;
  Object.defineProperty(navigator, 'userAgentData', {get: () => ({
    brands, mobile: false, platform: 'Windows',
    getHighEntropyValues: async () => ({brands, mobile: false, platform: 'Windows', architecture: 'x86', bitness: '64', platformVersion: '15.0.0'}),
    toJSON: () => ({brands, mobile: false, platform: 'Windows'})
  })});
}
