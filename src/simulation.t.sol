import "ds-test/test.sol";

interface UniV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);
}

interface Weth {
    function deposit() external payable;
    function transfer(address guy, uint256 wad) external;
    function approve(address guy, uint256 wad) external;
    function balanceOf(address guy) external returns (uint256);
}

interface Dai {
    function balanceOf(address guy) external returns (uint256);
}

contract Guy {
    UniV2Router02 uniRouter;
    Weth weth;
    constructor () public {
        uniRouter = UniV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        weth = Weth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        weth.approve(address(uniRouter), uint256(-1));
    }
    function swapExactTokensForTokens (
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        uniRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }
}

contract SimulationTests is DSTest {
    uint256 WAD = 1E18;
    Guy ali;
    Weth weth;
    Dai dai;
    function setUp() public {
        ali = new Guy();
        weth = Weth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        weth.deposit{value: 2 * WAD}();
        weth.transfer(address(ali), 2 * WAD);
        dai = Dai(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    }

    function testSwap() public {
        uint256 amountIn = 1 * WAD;
        uint256 amountOutMin = 1500 * WAD;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(dai);
        address to = address(ali);
        uint256 deadline = block.timestamp;
        uint256 wethPre = weth.balanceOf(address(ali));
        uint256 daiPre = dai.balanceOf(address(ali));
        ali.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        uint256 wethPost = weth.balanceOf(address(ali));
        uint256 daiPost = dai.balanceOf(address(ali));
        assertEq(wethPost, wethPre - amountIn);
        assertGe(daiPost, daiPre + amountOutMin);
    }
}
