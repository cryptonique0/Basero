test('security: should not allow prototype pollution', () => {
  const obj = {};
  const payload = JSON.parse('{"__proto__": {"polluted": true}}');
  Object.assign(obj, payload);
  expect({}.polluted).toBe(undefined);
});
