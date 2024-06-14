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
 
contract TestContract is Test{
    //Mainnet addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //18 decimals
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //18 decimals
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //6 decimals
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA; //18 decimals
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; //8 decimals

    address constant UniFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant AaveAddressesProvider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    LeverageTrading public leverageContract;

    address owner = address(1);

    function setUp() public {
        vm.startPrank(owner);
        leverageContract = new LeverageTrading(AaveAddressesProvider, UniFactory);
        vm.stopPrank();

        
       
        //deal(address(USDC), owner, 1000 * (10**6)); // 1000 US dollars
        //deal(address(WBTC), owner, 10 * (10**8)); // 10 BTC coins (~$67,000 USD)
        //deal(address(LINK), owner, 1000 ether); // 1000 link coins (~$15 USD)

        vm.label(address(leverageContract), "LeverageTrading Contract");
        vm.label(owner, "Owner");
    }   


    function testDepositFunds() public {
        deal(address(WETH), owner, 100 ether); // 1000 ethereum coins (~$3500 USD)
        vm.startPrank(owner);
        IERC20(WETH).approve(address(leverageContract), 100 ether);
        leverageContract.depositFunds(address(WETH), 100 ether);

        assertEq(IERC20(WETH).balanceOf(address(leverageContract)), 100 ether, "Funds not deposited correctly");
        vm.stopPrank();
    }


    function testWithdrawFunds() public {
        deal(address(WETH), owner, 100 ether); // 1000 ethereum coins (~$3500 USD)
        vm.startPrank(owner);
        IERC20(WETH).approve(address(leverageContract), 100 ether);
        leverageContract.depositFunds(address(WETH), 100 ether);

        leverageContract.withdrawAll(address(WETH));

        assertEq(IERC20(WETH).balanceOf(address(leverageContract)), 0, "Funds not withdrawn correctly");
        assertEq(IERC20(WETH).balanceOf(address(owner)), 100 ether, "Owner did not receive the withdrawn funds");
        vm.stopPrank();
    }

    function test_create_WETH_USDC_leverage(uint16 marginAmount) public {
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
            uniFeeTier: 3000,
            decimalOfDebt: 6,
            decimalOfLeverage: 18,
            threshold: 100, //1% slippage & price difference tolerance
            interestRateMode: 2

    });

        (address _debtToken, address _leverageToken, uint256 _marginAmount, uint24 _uniFeeTier, uint8 _decimalOfDebt, uint8 _decimalOfLeverage, uint24 _threshold) = leverageContract.getPositionInfo(positionId);

        assertEq(_debtToken, address(USDC), "Debt token mismatch");
        assertEq(_leverageToken, address(WETH), "Leverage token mismatch");
        assertEq(_marginAmount, margin, "Margin amount mismatch");
        assertEq(_uniFeeTier, 3000, "Uniswap fee tier mismatch");
        assertEq(_decimalOfDebt, 6, "Decimal of debt token mismatch");
        assertEq(_decimalOfLeverage, 18, "Decimal of leverage token mismatch");
        assertEq(_threshold, 100, "Threshold mismatch");

        vm.stopPrank();
    }


    function test_create_USDC_WETH_leverage(uint8 marginAmount) public {
        vm.startPrank(owner);
        vm.assume(marginAmount > 0);

        uint256 margin = uint256(marginAmount) * (10 ** 17); //0.01 eth to 25.5 eth

        deal(address(WETH), owner, 100 ether);

        IERC20(WETH).approve(address(leverageContract), 100 ether);

        leverageContract.depositFunds(WETH, margin);
        leverageContract.depositFunds(WETH, 5 ether); //buffer

        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(WETH),
            leverageToken: address(USDC),
            uniFeeTier: 3000,
            decimalOfDebt: 18,
            decimalOfLeverage: 6,
            threshold: 100, //1% slippage & price difference tolerance
            interestRateMode: 2
    });

        (address _debtToken, address _leverageToken, uint256 _marginAmount, uint24 _uniFeeTier, uint8 _decimalOfDebt, uint8 _decimalOfLeverage, uint24 _threshold) = leverageContract.getPositionInfo(positionId);

        assertEq(_debtToken, address(WETH), "Debt token mismatch");
        assertEq(_leverageToken, address(USDC), "Leverage token mismatch");
        assertEq(_marginAmount, margin, "Margin amount mismatch");
        assertEq(_uniFeeTier, 3000, "Uniswap fee tier mismatch");
        assertEq(_decimalOfDebt, 18, "Decimal of debt token mismatch");
        assertEq(_decimalOfLeverage, 6, "Decimal of leverage token mismatch");
        assertEq(_threshold, 100, "Threshold mismatch");

        vm.stopPrank();
    }


    function test_create_WBTC_DAI_leverage(uint8 marginAmount) public {
        vm.startPrank(owner);
        vm.assume(marginAmount > 0);

        uint256 margin = uint256(marginAmount) * (10 ** 6); //0.01 btc to 2.55 btc

        deal(address(WBTC), owner, 100 * (10**8));

        IERC20(WBTC).approve(address(leverageContract), 100 * (10**8));

        leverageContract.depositFunds(WBTC, margin);
        leverageContract.depositFunds(WBTC, 5 * (10**7)); //buffer

        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(WBTC),
            leverageToken: address(DAI),
            uniFeeTier: 3000,
            decimalOfDebt: 8,
            decimalOfLeverage: 18,
            threshold: 100,
            interestRateMode: 2
    });

        (address _debtToken, address _leverageToken, uint256 _marginAmount, uint24 _uniFeeTier, uint8 _decimalOfDebt, uint8 _decimalOfLeverage, uint24 _threshold) = leverageContract.getPositionInfo(positionId);

        assertEq(_debtToken, address(WBTC), "Debt token mismatch");
        assertEq(_leverageToken, address(DAI), "Leverage token mismatch");
        assertEq(_marginAmount, margin, "Margin amount mismatch");
        assertEq(_uniFeeTier, 3000, "Uniswap fee tier mismatch");
        assertEq(_decimalOfDebt, 8, "Decimal of debt token mismatch");
        assertEq(_decimalOfLeverage, 18, "Decimal of leverage token mismatch");
        assertEq(_threshold, 100, "Threshold mismatch");

        vm.stopPrank();
    }

        function test_create_WETH_WBTC_leverage(uint8 marginAmount) public {
        vm.startPrank(owner);
        vm.assume(marginAmount > 0);

        uint256 margin = uint256(marginAmount) * (10 ** 17); //0.01 eth to 25.5 eth

        deal(address(WETH), owner, 100 ether);

        IERC20(WETH).approve(address(leverageContract), 100 ether);

        leverageContract.depositFunds(WETH, margin);
        leverageContract.depositFunds(WETH, 5 ether); //buffer

        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(WETH),
            leverageToken: address(WBTC),
            uniFeeTier: 3000,
            decimalOfDebt: 18,
            decimalOfLeverage: 8,
            threshold: 100,
            interestRateMode: 2
    });

        (address _debtToken, address _leverageToken, uint256 _marginAmount, uint24 _uniFeeTier, uint8 _decimalOfDebt, uint8 _decimalOfLeverage, uint24 _threshold) = leverageContract.getPositionInfo(positionId);

        assertEq(_debtToken, address(WETH), "Debt token mismatch");
        assertEq(_leverageToken, address(WBTC), "Leverage token mismatch");
        assertEq(_marginAmount, margin, "Margin amount mismatch");
        assertEq(_uniFeeTier, 3000, "Uniswap fee tier mismatch");
        assertEq(_decimalOfDebt, 18, "Decimal of debt token mismatch");
        assertEq(_decimalOfLeverage, 8, "Decimal of leverage token mismatch");
        assertEq(_threshold, 100, "Threshold mismatch");

        vm.stopPrank();
    }

        function test_create_WETH_DAI_leverage(uint8 marginAmount) public {
        vm.startPrank(owner);
        vm.assume(marginAmount > 0);

        uint256 margin = uint256(marginAmount) * (10 ** 17); //0.01 eth to 25.5 eth

        deal(address(WETH), owner, 100 ether);

        IERC20(WETH).approve(address(leverageContract), 100 ether);

        leverageContract.depositFunds(WETH, margin);
        leverageContract.depositFunds(WETH, 5 ether); //buffer

        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(WETH),
            leverageToken: address(DAI),
            uniFeeTier: 3000,
            decimalOfDebt: 18,
            decimalOfLeverage: 18,
            threshold: 100,
            interestRateMode: 2
    });

        (address _debtToken, address _leverageToken, uint256 _marginAmount, uint24 _uniFeeTier, uint8 _decimalOfDebt, uint8 _decimalOfLeverage, uint24 _threshold) = leverageContract.getPositionInfo(positionId);

        assertEq(_debtToken, address(WETH), "Debt token mismatch");
        assertEq(_leverageToken, address(DAI), "Leverage token mismatch");
        assertEq(_marginAmount, margin, "Margin amount mismatch");
        assertEq(_uniFeeTier, 3000, "Uniswap fee tier mismatch");
        assertEq(_decimalOfDebt, 18, "Decimal of debt token mismatch");
        assertEq(_decimalOfLeverage, 18, "Decimal of leverage token mismatch");
        assertEq(_threshold, 100, "Threshold mismatch");
        assertEq(leverageContract.getInterestRateMode(positionId), 2, "Interest rate mode mismatch");

        vm.stopPrank();
    }


    function test_supply_to_aave(uint8 supplyAmount) public {
        vm.startPrank(owner);
        vm.assume(supplyAmount > 0);

        uint256 margin = uint256(100) * (10**6); //100 USDC

        deal(address(USDC), owner, uint256(1000) * (10**6));

        IERC20(USDC).approve(address(leverageContract), uint256(1000) * (10**6));

        leverageContract.depositFunds(USDC, margin);
        leverageContract.depositFunds(USDC, 10 * (10**6)); //buffer


        uint8 positionId = leverageContract.createPosition({
            marginAmount: margin,
            debtToken: address(USDC),
            leverageToken: address(WETH),
            uniFeeTier: 3000,
            decimalOfDebt: 6,
            decimalOfLeverage: 18,
            threshold: 100,
            interestRateMode: 2
    });

        (uint collateral_before,) = leverageContract.getPositionInfoAll();

        deal(address(WETH), owner, 1000 * (1 ether));
        IERC20(WETH).approve(address(leverageContract), uint256(supplyAmount) * (10**16));
        leverageContract.depositFunds(WETH, uint256(supplyAmount) * (10**16));

        leverageContract.supplyToAave(uint256(supplyAmount) * (10**16), positionId);

        (uint collateral_after,) = leverageContract.getPositionInfoAll();

        assertGt(collateral_after,collateral_before, "supply didnt work");

        vm.stopPrank();
    }
}

