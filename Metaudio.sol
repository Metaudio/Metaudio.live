// SPDX-License-Identifier: MIT
Project Meta Audio 


pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./access/Ownable.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract MetaAudio is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string constant _NAME = "Metaudio";
    string constant _SYMBOL = "Metaudio";
    uint8 constant _DECIMALS = 8;

    uint256 private constant _MAX = ~uint256(0);
    uint256 private _tTotal = 1000000000000000 * (10**_DECIMALS); // 1 Quadrilion MetaAudio
    uint256 private _rTotal = (_MAX - (_MAX % _tTotal));
    uint256 private _tFeeTotal;

    //  +---------------------------+-----+------+------------+---------+
    //  |                           | LP% | Metaudio% | Marketing% | Total % |
    //  +---------------------------+-----+------+------------+---------+
    //  | Normal Buy                | 2   |  3  |    5       |   10    |
    //  | Normal Sell               | 3   | 6    |    6       |   15    |
    //  +---------------------------+-----+------+------------+---------+

    uint8 public liquidityFeeOnBuy = 2;
    uint8 public marketingFeeOnBuy = 5;
    uint8 public MetaudiodistributionFeeOnBuy = 3;

    uint8 public liquidityFeeOnSell = 3;
    uint8 public marketingFeeOnSell = 6;
    uint8 public MetaudiodistributionFeeOnSell = 6;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;

    address[] private _excluded;

    IUniswapV2Router02 public pcsV2Router;
    address public pcsV2Pair;

    address public marketingWallet;
    bool public swapEnabled = true;

    uint256 public maxTxAmount = _tTotal.mul(1).div(10**2); // 1% of total supply
    uint256 public amountOfTokensToAddToLiquidityThreshold =
        maxTxAmount.mul(50).div(10**2); // 50% of max transaction amount

    bool public swapAndLiquifyEnabled = true;
    bool inSwapAndLiquify;

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    event SwapAndLiquify(uint256 ethReceived, uint256 tokensIntoLiqudity);

    constructor() {
        IUniswapV2Router02 _pancakeswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );

        marketingWallet = 0x7E8cC19874E3B01683B2c94fFdE6e0947c2D4EE8;

        pcsV2Pair = IUniswapV2Factory(_pancakeswapV2Router.factory())
            .createPair(address(this), _pancakeswapV2Router.WETH());
        pcsV2Router = _pancakeswapV2Router;
        _allowances[address(this)][address(pcsV2Router)] = _MAX;

        _rOwned[msg.sender] = _rTotal;
        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;

        emit Transfer(address(0), msg.sender, _tTotal);
    }

    receive() external payable {}

    // Back-Up withdraw, in case BNB gets sent in here
    // NOTE: This function is to be called if and only if BNB gets sent into this contract.
    // On no other occurence should this function be called.
    function withdrawEthInWei(address payable recipient, uint256 amount)
        external
        onlyOwner
    {
        require(recipient != address(0), "Invalid Recipient!");
        require(amount > 0, "Invalid Amount!");
        recipient.transfer(amount);
    }

    // Withdraw BEP20 tokens sent to this contract
    // NOTE: This function is to be called if and only if BEP20 tokens gets sent into this contract.
    // On no other occurence should this function be called. \

    function withdrawTokens(address token, address recipient)
        external
        onlyOwner
    {
        require(token != address(0), "Invalid Token!");
        require(recipient != address(0), "Invalid Recipient!");

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(recipient, balance);
        }
    }

    //  -----------------------------
    //  SETTERS (PROTECTED)
    //  -----------------------------
    function excludeFromReflection(address account) public onlyOwner {
        _excludeFromReflection(account);
    }

    function includeInReflection(address account) external onlyOwner {
        _includeInReflection(account);
    }

    function setIsExcludedFromFee(address account, bool flag)
        external
        onlyOwner
    {
        _setIsExcludedFromFee(account, flag);
    }

    function changeFeesForNormalBuy(
        uint8 _liquidityFeeOnBuy,
        uint8 _marketingFeeOnBuy,
        uint8 _MetaudiodistributionFeeOnBuy
    ) external onlyOwner {
        liquidityFeeOnBuy = _liquidityFeeOnBuy;
        marketingFeeOnBuy = _marketingFeeOnBuy;
        MetaudiodistributionFeeOnBuy = _MetaudiodistributionFeeOnBuy;
    }

    function changeFeesForNormalSell(
        uint8 _liquidityFeeOnSell,
        uint8 _marketingFeeOnSell,
        uint8 _MetaudiodistributionFeeOnSell
    ) external onlyOwner {
        liquidityFeeOnSell = _liquidityFeeOnSell;
        marketingFeeOnSell = _marketingFeeOnSell;
        MetaudiodistributionFeeOnSell = _MetaudiodistributionFeeOnSell;
    }

    function updateMarketingWallet(address _marketingWallet) external onlyOwner {
        require(_marketingWallet != address(0), "Zero address not allowed!");
        marketingWallet = _marketingWallet;
    }

    function updateAmountOfTokensToAddToLiquidityThreshold(
        uint256 _amountOfTokensToAddToLiquidityThreshold
    ) external onlyOwner {
        amountOfTokensToAddToLiquidityThreshold =
            _amountOfTokensToAddToLiquidityThreshold *
            (10**_DECIMALS);
    }

    function updateSwapAndLiquifyEnabled(bool _swapAndLiquifyEnabled)
        external
        onlyOwner
    {
        require(
            swapAndLiquifyEnabled != _swapAndLiquifyEnabled,
            "Value already exists!"
        );
        swapAndLiquifyEnabled = _swapAndLiquifyEnabled;
    }

    function setSwapEnabled(bool _swapEnabled) external onlyOwner {
        require(swapEnabled != _swapEnabled, "Value already exists!");
        swapEnabled = _swapEnabled;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        maxTxAmount = _tTotal.mul(maxTxPercent).div(100);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "BEP20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "BEP20: decreased allowance below zero"
            )
        );
        return true;
    }

    //  -----------------------------
    //  GETTERS
    //  -----------------------------
    function name() public pure returns (string memory) {
        return _NAME;
    }

    function symbol() public pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function isExcludedFromReflection(address account)
        public
        view
        returns (bool)
    {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromToken(uint256 tAmount)
        public
        view
        returns (uint256)
    {
        uint256 rAmount = tAmount.mul(_getRate());
        return rAmount;
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    //  -----------------------------
    //  INTERNAL
    //  -----------------------------
    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }

        if (rSupply < _rTotal.div(_tTotal)) {
            return (_rTotal, _tTotal);
        }
        return (rSupply, tSupply);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "BEP20: Transfer amount must be greater than zero");

        require(swapEnabled == true, "Swap Is Disabled!");

        if (sender != owner() && recipient != owner())
            require(
                amount <= maxTxAmount,
                "Transfer amount exceeds the maxTxAmount"
            );

        if (inSwapAndLiquify) {
            _basicTransfer(sender, recipient, amount);
            return;
        }

        if (_shouldSwapBack()) _swapAndAddToLiquidity();

        if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            _basicTransfer(sender, recipient, amount);
        } else {
            if (recipient == pcsV2Pair) {
                _normalSell(sender, recipient, amount);
            } else if (sender == pcsV2Pair) {
                _normalBuy(sender, recipient, amount);
            } else {
                _basicTransfer(sender, recipient, amount);
            }
        }
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        uint256 rAmount = reflectionFromToken(amount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        if (_isExcluded[sender]) _tOwned[sender] = _tOwned[sender].sub(amount);
        if (_isExcluded[recipient])
            _tOwned[recipient] = _tOwned[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _normalBuy(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = amount.mul(currentRate);
        uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnBuy).mul(
            currentRate
        );
        uint256 rNftdistributionFee = amount
            .div(100)
            .mul(MetaudiodistributionFeeOnBuy)
            .mul(currentRate);
        uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnBuy).mul(
            currentRate
        );
        uint256 rTransferAmount = rAmount
            .sub(rLiquidityFee)
            .sub(rNftdistributionFee)
            .sub(rMarketingFee);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidityFee);
        if (_isExcluded[sender]) _tOwned[sender] = _tOwned[sender].sub(amount);
        if (_isExcluded[recipient])
            _tOwned[recipient] = _tOwned[recipient].add(
                rTransferAmount.div(currentRate)
            );
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(
                rLiquidityFee.div(currentRate)
            );

        emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
        emit Transfer(sender, address(this), (rLiquidityFee).div(currentRate));

        _sendToMarketingWallet(sender, rMarketingFee.div(currentRate), rMarketingFee);
        _reflectFee(rNftdistributionFee, rNftdistributionFee.div(currentRate));
    }

    function _normalSell(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = amount.mul(currentRate);
        uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnSell).mul(
            currentRate
        );
        uint256 rMetaudiodistributionFee = amount
            .div(100)
            .mul(MetaudiodistributionFeeOnSell)
            .mul(currentRate);
        uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnSell).mul(
            currentRate
        );
        uint256 rTransferAmount = rAmount
            .sub(rLiquidityFee)
            .sub(rMetaudiodistributionFee)
            .sub(rMarketingFee);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidityFee);
        if (_isExcluded[sender]) _tOwned[sender] = _tOwned[sender].sub(amount);
        if (_isExcluded[recipient])
            _tOwned[recipient] = _tOwned[recipient].add(
                rTransferAmount.div(currentRate)
            );
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(
                rLiquidityFee.div(currentRate)
            );

        emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
        emit Transfer(sender, address(this), rLiquidityFee.div(currentRate));

        _sendToMarketingWallet(sender, rMarketingFee.div(currentRate), rMarketingFee);
        _reflectFee(rMetaudiodistributionFee, rMetaudiodistributionFee.div(currentRate));
    }

    function _sendToMarketingWallet(address sender, uint256 tMarketingFee, uint256 rMarketingFee) private {
        _rOwned[marketingWallet] = _rOwned[marketingWallet].add(rMarketingFee);
        if (_isExcluded[marketingWallet]) _tOwned[marketingWallet] = _tOwned[marketingWallet].add(tMarketingFee);
        emit Transfer(sender, marketingWallet, tMarketingFee);
    }

    function _shouldSwapBack() private view returns (bool) {
        return
            msg.sender != pcsV2Pair &&
            !inSwapAndLiquify &&
            swapAndLiquifyEnabled &&
            balanceOf(address(this)) >= amountOfTokensToAddToLiquidityThreshold;
    }

    function _swapAndAddToLiquidity() private lockTheSwap {
        uint256 tokenAmountForLiquidity = amountOfTokensToAddToLiquidityThreshold;
        uint256 amountToSwap = tokenAmountForLiquidity.div(2);
        uint256 amountAnotherHalf = tokenAmountForLiquidity.sub(amountToSwap);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pcsV2Router.WETH();

        uint256 balanceBefore = address(this).balance;

        pcsV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );

        uint256 differenceBnb = address(this).balance.sub(balanceBefore);

        pcsV2Router.addLiquidityETH{value: differenceBnb}(
            address(this),
            amountAnotherHalf,
            0,
            0,
            owner(),
            block.timestamp.add(30)
        );

        emit SwapAndLiquify(differenceBnb, amountToSwap);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _excludeFromReflection(address account) private {
        // require(account !=  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude PancakeSwap router.');
        require(!_isExcluded[account], "Account is already excluded");

        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function _includeInReflection(address account) private {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _rOwned[account] = reflectionFromToken(_tOwned[account]);
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _setIsExcludedFromFee(address account, bool flag) private {
        _isExcludedFromFee[account] = flag;
    }
}
