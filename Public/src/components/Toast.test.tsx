import { render } from "@testing-library/react";
import { Toast } from "./Toast";

describe("Toast", () => {
  it("renders message", () => {
    const { getByText } = render(<Toast message="Hello" onClose={() => {}} />);
    expect(getByText("Hello")).toBeInTheDocument();
  });
});
