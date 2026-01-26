import { render } from "@testing-library/react";
import { LastTransactionPanel } from "./LastTransactionPanel";

describe("LastTransactionPanel", () => {
  it("shows no recent transaction", () => {
    const { getByText } = render(<LastTransactionPanel tx={null} />);
    expect(getByText("No recent transaction.")).toBeInTheDocument();
  });
  it("shows transaction details", () => {
    const tx = { hash: "0x123", status: "success", time: "now" };
    const { getByText } = render(<LastTransactionPanel tx={tx} />);
    expect(getByText("0x123")).toBeInTheDocument();
    expect(getByText("success")).toBeInTheDocument();
    expect(getByText("now")).toBeInTheDocument();
  });
});
