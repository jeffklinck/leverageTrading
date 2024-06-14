// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import '../LeverageTrading.sol';
import 'forge-std/Test.sol';

import 'forge-std/console.sol';


import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import 'aave-v3-core/contracts/interfaces/IPool.sol';
import 'aave-v3-core/contracts/interfaces/IPoolDataProvider.sol';
import 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import 'aave-v3-core/contracts/interfaces/IPriceOracle.sol';

import 'v3-periphery/contracts/libraries/TransferHelper.sol';
import 'v3-periphery/contracts/interfaces/ISwapRouter.sol';

import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import 'v3-core/contracts/interfaces/IUniswapV3Factory.sol';

 
contract TestContract is Test{
    //Mainnet addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //18 decimals
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //6 decimals

    address constant UniFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant AaveAddressesProvider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    LeverageTrading public leverageContract;

    address public uniPool;

    address owner = address(1);

    ISwapRouter public swapRouter;

    IUniswapV3Factory public uniFactory;


    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    uint160 private constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    function setUp() public {
        vm.startPrank(owner);
        leverageContract = new LeverageTrading(AaveAddressesProvider, UniFactory);
        

        
       
        //deal(address(USDC), owner, 1000 * (10**6)); // 1000 US dollars
        //deal(address(WBTC), owner, 10 * (10**8)); // 10 BTC coins (~$67,000 USD)
        //deal(address(LINK), owner, 1000 ether); // 1000 link coins (~$15 USD)

        vm.label(address(leverageContract), "LeverageTrading Contract");
        vm.label(owner, "Owner");

        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        uniFactory = IUniswapV3Factory(UniFactory);
        uniPool = uniFactory.getPool(USDC, WETH, 500);
        vm.stopPrank();
    }   


    function test_overall(uint16 marginAmount) public {
        vm.startPrank(owner);
        vm.assume(marginAmount > 0);

        uint256 margin = uint256(marginAmount) * 10**5; //0.001 USDC to 6555.4 USDC

        deal(address(USDC), owner, 100000 * (10**6));

        IERC20(USDC).approve(address(leverageContract), 100000 * (10**6));

        leverageContract.depositFunds(USDC, margin);
        leverageContract.depositFunds(USDC, 7000 * (10**6)); //buffer

        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(USDC),
            leverageToken: address(WETH),
            uniFeeTier: 500,
            decimalOfDebt: 6,
            decimalOfLeverage: 18,
            threshold: 100, //1% slippage & price difference tolerance
            interestRateMode: 2
    });


        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniPool).slot0();
        uint256 priceX96_1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / ((1 << 192));
        console.log("price before:", priceX96_1);

        /* INCREASE ETH PRICE
        deal(address(USDC), owner, 51000000 * (10**6));

        TransferHelper.safeApprove(USDC, address(swapRouter), 51000000 * (10**6));

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: 3000,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: 10000000 * (10**6),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        */

        //DECREASE ETH PRICE
        deal(address(WETH), owner, 130 ether);

        TransferHelper.safeApprove(WETH, address(swapRouter), 130 ether);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: 500,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: 100 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        

    

        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniPool).slot0();
        uint256 priceX96_2 = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / ((1 << 192));
        console.log("price after:", priceX96_2);

        console.log('margin amount: ', margin);

        deal(address(USDC), owner, 0);
        deal(address(WETH), owner, 0);

        console.log("our USDC balance before: ", IERC20(USDC).balanceOf(address(owner)));
        console.log("our WETH balance before: ", IERC20(WETH).balanceOf(address(owner)));

        leverageContract.closePosition(positionId);

        console.log("our USDC balance after: ", IERC20(USDC).balanceOf(address(owner)));
        console.log("our WETH balance after: ", IERC20(WETH).balanceOf(address(owner)));


        vm.stopPrank();
    }

}

