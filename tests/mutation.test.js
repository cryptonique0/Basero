// Example mutation test (pseudo, for illustration)
test('mutation: add function', () => {
  function add(a, b) { return a + b; }
  expect(add(2, 2)).toBe(4);
});
// Use Stryker or similar for real mutation testing
