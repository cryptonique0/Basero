test('performance: sum 1M numbers', () => {
  const start = Date.now();
  let sum = 0;
  for (let i = 0; i < 1_000_000; i++) sum += i;
  const elapsed = Date.now() - start;
  expect(elapsed).toBeLessThan(1000); // Should be fast
});
