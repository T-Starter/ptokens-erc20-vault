pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "./IWETH.sol";
import "./Withdrawable.sol";

contract PERC20OnEosVault is Withdrawable, IERC777Recipient {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    EnumerableSet.AddressSet private supportedTokens;
    address public PNETWORK;
    IWETH public weth;

    event PegIn(address _tokenAddress, address _tokenSender, uint256 _tokenAmount, string _destinationAddress);

    constructor(
        address _weth,
        address [] memory _tokensToSupport
    ) public {
        PNETWORK = msg.sender;
        for (uint256 i = 0; i < _tokensToSupport.length; i++) {
            supportedTokens.add(_tokensToSupport[i]);
        }
        weth = IWETH(_weth);
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    modifier onlyPNetwork() {
        require(msg.sender == PNETWORK, "Caller must be PNETWORK address!");
        _;
    }

    receive() external payable {
        require(msg.sender == address(weth));
    }

    function setWeth(address _weth) external onlyPNetwork {
        weth = IWETH(_weth);
    }

    function setPNetwork(address _pnetwork) external onlyPNetwork {
        PNETWORK = _pnetwork;
    }

    function IS_TOKEN_SUPPORTED(address _token) external view returns(bool) {
        return supportedTokens.contains(_token);
    }

    function _owner() internal override returns(address) {
        return PNETWORK;
    }

    function adminWithdrawAllowed(address asset) internal override view returns(uint) {
        return supportedTokens.contains(asset) ? 0 : super.adminWithdrawAllowed(asset);
    }

    function addSupportedToken(
        address _tokenAddress
    )
        external
        onlyPNetwork
        returns (bool SUCCESS)
    {
        supportedTokens.add(_tokenAddress);
        return true;
    }

    function removeSupportedToken(
        address _tokenAddress
    )
        external
        onlyPNetwork
        returns (bool SUCCESS)
    {
        return supportedTokens.remove(_tokenAddress);
    }

    function pegIn(
        uint256 _tokenAmount,
        address _tokenAddress,
        string calldata _destinationAddress
    )
        external
        returns (bool)
    {
        require(supportedTokens.contains(_tokenAddress), "Token at supplied address is NOT supported!");
        require(_tokenAmount > 0, "Token amount must be greater than zero!");
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenAmount);
        emit PegIn(_tokenAddress, msg.sender, _tokenAmount, _destinationAddress);
        return true;
    }

    /**
     * @dev Implementation of IERC777Recipient.
     */
    function tokensReceived(
        address /*operator*/,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata /*operatorData*/
    ) external override {
        address _tokenAddress = msg.sender;
        require(supportedTokens.contains(_tokenAddress), "caller is not a supported ERC777 token!");
        require(to == address(this), "Token receiver is not this contract");
        require(amount > 0, "Token amount must be greater than zero!");
        (bytes32 tag, string memory _destinationAddress) = abi.decode(userData, (bytes32, string));
        require(tag == keccak256("ERC777-pegIn"), "Invalid tag for automatic pegIn on ERC777 send");
        emit PegIn(_tokenAddress, from, amount, _destinationAddress);
    }

    function pegInEth(string calldata _destinationAddress)
        external
        payable
        returns (bool)
    {
        require(supportedTokens.contains(address(weth)), "WETH is NOT supported!");
        require(msg.value > 0, "Ethers amount must be greater than zero!");
        weth.deposit.value(msg.value)();
        emit PegIn(address(weth), msg.sender, msg.value, _destinationAddress);
        return true;
    }

    function pegOut(
        address payable _tokenRecipient,
        address _tokenAddress,
        uint256 _tokenAmount
    )
        external
        onlyPNetwork
        returns (bool)
    {
        if (_tokenAddress == address(weth)) {
            weth.withdraw(_tokenAmount);
            _tokenRecipient.transfer(_tokenAmount);
        } else {
            IERC20(_tokenAddress).safeTransfer(_tokenRecipient, _tokenAmount);
        }
        return true;
    }

    function migrate(
        address payable _to
    )
        external
        onlyPNetwork
    {
        for (uint256 i = 0; i < supportedTokens.length(); i++) {
            address tokenAddress = supportedTokens.at(i);
            _migrateSingle(_to, tokenAddress);
        }
    }

    function destroy()
        external
        onlyPNetwork
    {
        for (uint256 i = 0; i < supportedTokens.length(); i++) {
            address tokenAddress = supportedTokens.at(i);
            require(IERC20(tokenAddress).balanceOf(address(this)) == 0, "Balance of supported tokens must be 0");
        }
        selfdestruct(msg.sender);
    }

    function migrateSingle(
        address payable _to,
        address _tokenAddress
    )
        external
        onlyPNetwork
    {
        _migrateSingle(_to, _tokenAddress);
    }

    function _migrateSingle(
        address payable _to,
        address _tokenAddress
    )
        private
    {
        if (supportedTokens.contains(_tokenAddress)) {
            uint balance = IERC20(_tokenAddress).balanceOf(address(this));
            IERC20(_tokenAddress).safeTransfer(_to, balance);
            supportedTokens.remove(_tokenAddress);
        }
    }
}
