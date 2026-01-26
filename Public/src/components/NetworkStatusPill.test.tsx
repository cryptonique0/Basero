import { render } from "@testing-library/react";
import { NetworkStatusPill } from "./NetworkStatusPill";

describe("NetworkStatusPill", () => {
  it("renders online status", () => {
    const { getByText } = render(<NetworkStatusPill status="online" />);
    expect(getByText("Online")).toBeInTheDocument();
  });
  it("renders offline status", () => {
    const { getByText } = render(<NetworkStatusPill status="offline" />);
    expect(getByText("Offline")).toBeInTheDocument();
  });
});
