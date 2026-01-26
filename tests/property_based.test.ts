import fc from 'fast-check';

describe('Property-based: string reversal', () => {
  it('should reverse twice to get original', () => {
    fc.assert(
      fc.property(fc.string(), str => {
        expect(str.split('').reverse().reverse().join('')).toBe(str);
      })
    );
  });
});
