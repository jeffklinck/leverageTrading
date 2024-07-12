// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import 'v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import 'v3-core/contracts/interfaces/IUniswapV3Factory.sol';

import 'aave-v3-core/contracts/interfaces/IPool.sol';
import 'aave-v3-core/contracts/interfaces/IPoolDataProvider.sol';
import 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import 'aave-v3-core/contracts/interfaces/IPriceOracle.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import 'forge-std/console.sol';



contract LeverageTrading is IUniswapV3SwapCallback{
    IPoolAddressesProvider public immutable addressesProvider;
    IPool public immutable lendingPool;
    IPoolDataProvider public immutable poolConfigurator;

    address public immutable priceOracle;

    IUniswapV3Factory public uniFactory;

    address owner;

    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    uint160 private constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    bool private create;
    //_addressesProvider for Aave optimism: 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
    //_factory for UniswapV3 optimism: 0x1F98431c8aD98523631AE4a59f267346ea31F984

    uint8 public ids;

    struct Position {
        address debtToken;
        address leverageToken;
        uint256 marginAmount;
        uint24 uniFeeTier;
        uint8 decimalOfDebt;
        uint8 decimalOfLeverage;
        uint24 threshold;
        uint256 interestRateMode;
    }

    mapping(uint8 => Position) public positions;
 
    constructor(address _addressesProvider, address _factory) {
        owner = msg.sender;

        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        lendingPool = IPool(addressesProvider.getPool());
        poolConfigurator = IPoolDataProvider(addressesProvider.getPoolDataProvider());
        priceOracle = addressesProvider.getPriceOracle();

        uniFactory = IUniswapV3Factory(_factory);

        ids = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function depositFunds(address asset, uint256 amount) onlyOwner external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawFunds(address asset, uint256 amount) private {

        IERC20(asset).transfer(owner, amount);
    }

    function withdrawAll(address asset) onlyOwner external {
        IERC20(asset).transfer(owner, IERC20(asset).balanceOf(address(this)));
    }

    function supplyToAave(uint256 amount, uint8 id) onlyOwner external {
        Position memory position = positions[id];
        address asset = position.leverageToken;
        IERC20(asset).approve(addressesProvider.getPool(), amount);
        lendingPool.supply({
            asset: asset,
            amount: amount,
            onBehalfOf: address(this),
            referralCode: 0
        });
    }

    function getPositionInfoAll() onlyOwner external view returns (uint256, uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = lendingPool.getUserAccountData(address(this));
        return (totalCollateralBase, totalDebtBase);
    }

    function getPositionInfo(uint8 id) onlyOwner external view returns (address, address, uint256, uint24, uint8, uint8, uint24) {
        return (positions[id].debtToken, positions[id].leverageToken, positions[id].marginAmount, positions[id].uniFeeTier, positions[id].decimalOfDebt, positions[id].decimalOfLeverage, positions[id].threshold);
    }

    function getInterestRateMode(uint8 id) onlyOwner external view returns (uint256) {
        return positions[id].interestRateMode;
    }

    function getUniPoolInfo(address token0, address token1, uint24 fee_tier) public view returns (address) {
        address uniPool = uniFactory.getPool(token0, token1, fee_tier);
        return uniPool;
    }

    function getLTV(address asset) public view returns (uint256) {
        (,uint256 ltv,,,,,,,,) = poolConfigurator.getReserveConfigurationData(asset);
        return ltv;
    }

    function maxBorrowAmount(address debtToken, uint8 decimalOfDebt) public view returns (uint256) {
        (,,uint256 availableBorrowsETH,,,) = lendingPool.getUserAccountData(address(this)); 
        uint256 debtTokenPriceInETH = IPriceOracle(priceOracle).getAssetPrice(debtToken); // 8 decimals
        uint256 maxBorrowableDebtTokenAmount = (availableBorrowsETH * (10**decimalOfDebt)) / debtTokenPriceInETH;

        return maxBorrowableDebtTokenAmount;
    }

    function price_x_for_y(uint256 amount, address token0, address token1, uint8 decimal0, uint8 decimal1) public view returns (uint256) {
        uint256 price = ((amount * (10**(18-decimal0))) * uint256(IPriceOracle(priceOracle).getAssetPrice(token0))) / uint256(IPriceOracle(priceOracle).getAssetPrice(token1));
        return price/(10**(18-decimal1)); // convert decimal to 8 decimals
    }

    function createPosition(
        uint256 marginAmount,
        address debtToken, //'margin' token, the base token
        address leverageToken, //'uniswap loan' token, the token that will be levered
        uint24 uniFeeTier,
        uint8 decimalOfDebt,
        uint8 decimalOfLeverage,
        uint24 threshold, //in bips
        uint256 interestRateMode
    ) onlyOwner external returns (uint8){
        Position memory position = Position(debtToken, leverageToken, marginAmount, uniFeeTier, decimalOfDebt, decimalOfLeverage, threshold, interestRateMode);

        positions[ids] = position;
        ids += 1;

        require (marginAmount > 0, "Margin amount must be greater than 0");

        create = true;

        address uniPool = getUniPoolInfo(position.debtToken, position.leverageToken, position.uniFeeTier);
        
        bool zeroForOne = IUniswapV3Pool(uniPool).token0() == position.debtToken ? true : false;

        uint256 ltv = getLTV(position.leverageToken);

        uint160 sqrtPriceLimitX96;
        
        uint256 amount_to_borrow = price_x_for_y((position.marginAmount * 10000)/(10000 - ltv), position.debtToken, position.leverageToken, position.decimalOfDebt, position.decimalOfLeverage);

        bytes memory data = abi.encode(
            uniPool,
            position.marginAmount,
            zeroForOne,
            position.leverageToken,
            position.debtToken,
            position.decimalOfDebt,
            position.threshold,
            position.interestRateMode
        );

        IUniswapV3Pool(uniPool).swap({
            recipient: address(this),
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amount_to_borrow),
            sqrtPriceLimitX96: sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
            data: data
        });

        return ids - 1;
    }

    function aaveLoan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 interestRateMode,
        uint8 decimalOfDebt
    ) private returns (uint256) {
        IERC20(tokenIn).approve(addressesProvider.getPool(), amountIn);
    

        lendingPool.supply({
            asset: address(tokenIn),
            amount: amountIn,
            onBehalfOf: address(this),
            referralCode: 0
        });

        lendingPool.setUserUseReserveAsCollateral(tokenIn, true);
        
        uint256 maxAmount = maxBorrowAmount(tokenOut, decimalOfDebt);

        lendingPool.borrow({
            asset: tokenOut, 
            amount: maxAmount, //maxAmount
            interestRateMode: interestRateMode, 
            referralCode: 0,
            onBehalfOf: address(this)
        });

        return maxAmount;
    }

    function aaveUnwind(
        address debtToken,
        address levergeToken,
        uint256 interestRateMode
    ) private {
        IERC20(debtToken).approve(addressesProvider.getPool(), IERC20(debtToken).balanceOf(address(this)));


        lendingPool.repay({
            asset: debtToken,
            amount: uint(int256(-1)), //debtAmount
            interestRateMode: interestRateMode,
            onBehalfOf: address(this)
        });


        lendingPool.withdraw({
            asset: levergeToken, 
            amount: type(uint).max,  //type(uint).max
            to: address(this)
        });

    }

    function get_debt_and_collateral_base(address debtToken, address leverageToken, uint8 debtDecimals, uint8 leverageDecimals) private view returns (uint256, uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = lendingPool.getUserAccountData(address(this));

        uint256 debtAmount = totalDebtBase * 10**debtDecimals/ IPriceOracle(priceOracle).getAssetPrice(debtToken);

        uint256 collateralAmount = totalCollateralBase * 10**leverageDecimals / IPriceOracle(priceOracle).getAssetPrice(leverageToken);

        return(debtAmount, collateralAmount);
    }

    function closePosition(
        uint8 id
    ) onlyOwner external {
        Position memory position = positions[id];

        address debtToken = position.debtToken;
        address leverageToken = position.leverageToken;
        uint24 uniFeeTier = position.uniFeeTier;
        uint8 decimalOfDebt = position.decimalOfDebt;
        uint8 decimalOfLeverage = position.decimalOfLeverage;
        uint256 interestRateMode = position.interestRateMode;

        create = false;
        
        (uint256 debtAmount, uint256 collateralAmount) = get_debt_and_collateral_base(debtToken, leverageToken, decimalOfDebt, decimalOfLeverage);

        address uniPool = getUniPoolInfo(debtToken, leverageToken, uniFeeTier);
        
        bool zeroForOne = IUniswapV3Pool(uniPool).token0() == debtToken ? false : true;

        uint160 sqrtPriceLimitX96;

        bytes memory data = abi.encode(
                uniPool,
                collateralAmount,
                zeroForOne,
                debtToken,
                leverageToken,
                interestRateMode
            );
        

        IUniswapV3Pool(uniPool).swap({
            recipient: address(this),
            zeroForOne: zeroForOne,
            amountSpecified: -int256(debtAmount),
            sqrtPriceLimitX96: sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
            data: data
        });
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        if (create) {
            (
                address uniPoolAdr,
                uint256 marginAmount,
                bool zeroForOne,
                address tokenIn,
                address tokenOut,
                uint8 decimalOfDebt,
                uint24 threshold,
                uint256 interestRateMode
            ) = abi.decode(
                data, (address, uint256, bool, address, address, uint8, uint24, uint256)
            );

            require(msg.sender == address(uniPoolAdr));

            uint256 amountOutReceived;
            uint256 amountIn;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));


            uint256 borrowedAmount = aaveLoan(tokenIn, tokenOut, amountOutReceived, interestRateMode, decimalOfDebt);

            require(amountIn - (amountIn * threshold)/10000 <= borrowedAmount + marginAmount, "Position not covered");

            IERC20(tokenOut).approve(address(uniPoolAdr), amountIn);
            IERC20(tokenOut).transfer(uniPoolAdr, amountIn);
        } else {
            (
                address uniPoolAdr,
                uint256 collateralAmount,
                bool zeroForOne,
                address debtToken,
                address leverageToken,
                uint256 interestRateMode
            ) = abi.decode(
                data, (address, uint256, bool, address, address, uint256)
            );

            require(msg.sender == address(uniPoolAdr));

            uint256 amountOutReceived;
            uint256 amountIn;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

            aaveUnwind(debtToken, leverageToken, interestRateMode);

            require(collateralAmount>=amountIn);

            IERC20(leverageToken).approve(address(uniPoolAdr), amountIn);
            IERC20(leverageToken).transfer(address(uniPoolAdr), amountIn);
            IERC20(leverageToken).approve(address(owner), collateralAmount - amountIn);
            withdrawFunds(leverageToken, collateralAmount - amountIn);
    }    
}
}
