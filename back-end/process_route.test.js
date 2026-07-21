const { interpolateTo50ms } = require("./process_route");

// Interpolation to 50 milli seconds tests

test("Interpolation between two separate points", () => {
  expect(
    interpolateTo50ms(
      [
        [0, 0, 0],
        [1, 0, 0],
      ],
      [0, 1],
    ),
  ).toStrictEqual([
    [0, 0],
    [0.05, 0],
    [0.1, 0],
    [0.15, 0],
    [0.2, 0],
    [0.25, 0],
    [0.3, 0],
    [0.35, 0],
    [0.4, 0],
    [0.45, 0],
    [0.5, 0],
    [0.55, 0],
    [0.6, 0],
    [0.65, 0],
    [0.7, 0],
    [0.75, 0],
    [0.8, 0],
    [0.85, 0],
    [0.9, 0],
    [0.95, 0],
    [1, 0],
  ]);
});

test("Interpolation between the same two points", () => {
  const expected = Array.from({ length: 21 }, () => [0, 0]);
  expect(
    interpolateTo50ms(
      [
        [0, 0, 0],
        [0, 0, 0],
      ],
      [0, 1],
    ),
  ).toStrictEqual(expected);
});

test("Six point interpolation", () => {
  const expected = [];
  for (let i = 0; i <= 10; i += 0.1) {
    expected.push([expect.closeTo(i), 0]);
  }
  expect(
    interpolateTo50ms(
      [
        [0, 0, 0],
        [2, 0, 0],
        [4, 0, 0],
        [6, 0, 0],
        [8, 0, 0],
        [10, 0, 0],
      ],
      [0, 1, 2, 3, 4, 5],
    ),
  ).toStrictEqual(expected);
});

test("2D Interpolation", () => {
    const expected = [];

})