// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./UboxNFT1155.sol";

contract UboxNFT1155Store is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ERC1155HolderUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    //keccak256("Mint(address caller,uint256 nonce,uint256 orderId,address nftAddress,uint256 tokenId,uint256 tokenAmount,address currency,uint256 paymentAmount,uint256 feeAmount,uint256 expiry)");
    bytes32 public constant MINT_TYPE_HASH = 0xcf1ddde23704de1991f9baec5c02d5d6e8c3c66579c65eb934edd664d7125d8c;
    //keccak256("Redeem(address caller,uint256 nonce,uint256 orderId,address nftAddress,uint256 tokenId,uint256 tokenAmount,address currency,uint256 refundAmount,uint256 expiry)");
    bytes32 public constant REDEEM_TYPE_HASH = 0x68b78eb1605f62476680bcf569d6c08f8be6dc8c7ad52a1438868cdc8f002ae3;

    address public bridgeAddress;
    address public feeAddress;
    address public managerAddress;
    address public signerAddress;
    mapping(address => uint256) public nonces;
    mapping(address => bool) nftItems;

    struct MintParam {
        uint256 orderId;
        address nftAddress;
        uint256 tokenId;
        uint256 tokenAmount;
        address currency;
        uint256 paymentAmount;
        uint256 feeAmount;
        uint256 expiry;
    }

    struct RedeemParam {
        uint256 orderId;
        address nftAddress;
        uint256 tokenId;
        uint256 tokenAmount;
        address currency;
        uint256 refundAmount;
        uint256 expiry;
    }

    event Mint(
        uint256 indexed orderId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 tokenAmount,
        address currency,
        uint256 paymentAmount,
        uint256 feeAmount,
        address recipient
    );

    event Redeem(
        uint256 indexed orderId,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 tokenAmount,
        address currency,
        uint256 refundAmount,
        address recipient
    );

    event SetSignerAddress(address indexed signerAddress);
    event SetFeeAddress(address indexed feeAddress);
    event SetManager(address indexed managerAddress);
    event AddUboxNFTItem(address indexed nftAddress, uint256 indexed tokenId, uint256 indexed maxSupply);
    event BridgeToNative(address indexed bridgeAddress, uint256 indexed bridgeAmount);

    modifier onlyManager() {
        require(managerAddress == _msgSender(), "UboxNFTStore: caller is not the mananger");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bridgeAddress,
        address _feeAddress,
        address _managerAddress,
        address _signerAddress
    ) public initializer {
        require(_bridgeAddress != address(0));
        require(_feeAddress != address(0));
        require(_managerAddress != address(0));
        require(_signerAddress != address(0));
        bridgeAddress = _bridgeAddress;
        feeAddress = _feeAddress;
        managerAddress = _managerAddress;
        signerAddress = _signerAddress;
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __EIP712_init("UboxNFT1155Store", "1");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function renounceOwnership() public virtual override onlyOwner {
        revert("UboxNFTStore: renounce ownership is not allowed");
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "UboxNFTStore: fee address can not be address(0)");
        feeAddress = _feeAddress;
        emit SetFeeAddress(feeAddress);
    }

    function setManager(address _managerAddress) external onlyOwner {
        require(_managerAddress != address(0), "UboxNFTStore: manager can not be address(0)");
        managerAddress = _managerAddress;
        emit SetManager(managerAddress);
    }

    function setSignerAddress(address _signerAddress) external onlyOwner {
        require(_signerAddress != address(0), "UboxNFTStore: signer address can not be address(0)");
        signerAddress = _signerAddress;
        emit SetSignerAddress(signerAddress);
    }

    function addUboxNFTItem(address _nftAddress, uint256 _tokenId, uint256 _maxSupply) external onlyManager {
        require(_nftAddress != address(0), "UboxNFTStore: nft address can not be address(0)");
        require(_maxSupply > 0, "UboxNFTStore: max supply must be greater than 0");
        if (!nftItems[_nftAddress]) {
            nftItems[_nftAddress] = true;
        }
        UboxNFT1155(_nftAddress).setMaxSupply(_tokenId, _maxSupply);
        emit AddUboxNFTItem(_nftAddress, _tokenId, _maxSupply);
    }

    function bridgeToNative(uint256 _amount) external onlyManager {
        require(address(this).balance >= _amount, "UboxNFTStore: amount can not exceed the balance");
        (bool success, ) = payable(bridgeAddress).call{value: _amount}("");
        require(success, "UboxNFTStore: transfer native coin failed");
        emit BridgeToNative(bridgeAddress, _amount);
    }

    function mint(MintParam calldata mintParam, bytes calldata signature) external payable nonReentrant whenNotPaused {
        require(block.timestamp < mintParam.expiry, "UboxNFTStore: signature is expired");
        require(nftItems[mintParam.nftAddress], "UboxNFTStore: nft address not exist");
        (uint256 tokenMinted, uint256 maxSupply) = UboxNFT1155(mintParam.nftAddress).totalMint(mintParam.tokenId);
        require(maxSupply > 0, "UboxNFTStore: token id does not exist");
        require(mintParam.tokenAmount > 0, "UboxNFTStore: token amount must be greater than 0");
        require(tokenMinted + mintParam.tokenAmount <= maxSupply, "UboxNFTStore: can not exceed the max supply");
        bytes memory structData = abi.encode(
            MINT_TYPE_HASH,
            msg.sender,
            nonces[msg.sender]++,
            mintParam.orderId,
            mintParam.nftAddress,
            mintParam.tokenId,
            mintParam.tokenAmount,
            mintParam.currency,
            mintParam.paymentAmount,
            mintParam.feeAmount,
            mintParam.expiry
        );
        bytes32 structHash = keccak256(structData);
        bytes32 digest = _hashTypedDataV4(structHash);
        address dataSigner = ECDSAUpgradeable.recover(digest, signature);
        require(dataSigner == signerAddress, "UboxNFTStore: invalid signature");
        if (mintParam.paymentAmount > 0) {
            bool isNativeCoin = mintParam.currency == address(1);
            if (isNativeCoin) {
                require(
                    mintParam.paymentAmount == msg.value,
                    "UboxNFTStore: the value of native coin passed by this transaction dose not match the payment amount"
                );
                if (mintParam.feeAmount > 0) {
                    (bool success, ) = payable(feeAddress).call{value: mintParam.feeAmount}("");
                    require(success, "UboxNFTStore: transfer native coin failed");
                }
            } else {
                IERC20Upgradeable(mintParam.currency).safeTransferFrom(
                    _msgSender(),
                    address(this),
                    mintParam.paymentAmount
                );
                if (mintParam.feeAmount > 0) {
                    IERC20Upgradeable(mintParam.currency).safeTransfer(feeAddress, mintParam.feeAmount);
                }
            }
        }
        UboxNFT1155(mintParam.nftAddress).mint(_msgSender(), mintParam.tokenId, mintParam.tokenAmount);
        emit Mint(
            mintParam.orderId,
            mintParam.nftAddress,
            mintParam.tokenId,
            mintParam.tokenAmount,
            mintParam.currency,
            mintParam.paymentAmount,
            mintParam.feeAmount,
            _msgSender()
        );
    }

    function redeem(RedeemParam calldata redeemParam, bytes calldata signature) external nonReentrant whenNotPaused {
        require(block.timestamp < redeemParam.expiry, "UboxNFTStore: signature is expired");
        require(nftItems[redeemParam.nftAddress], "UboxNFTStore: nft address not exist");
        (, uint256 maxSupply) = UboxNFT1155(redeemParam.nftAddress).totalMint(redeemParam.tokenId);
        require(maxSupply > 0, "UboxNFTStore: token id does not exist");
        require(redeemParam.tokenAmount > 0, "UboxNFTStore: token amount must be greater than 0");
        require(
            UboxNFT1155(redeemParam.nftAddress).balanceOf(_msgSender(), redeemParam.tokenId) >= redeemParam.tokenAmount,
            "UboxNFTStore: nft balance of the caller is not enough"
        );
        bytes memory structData = abi.encode(
            REDEEM_TYPE_HASH,
            msg.sender,
            nonces[msg.sender]++,
            redeemParam.orderId,
            redeemParam.nftAddress,
            redeemParam.tokenId,
            redeemParam.tokenAmount,
            redeemParam.currency,
            redeemParam.refundAmount,
            redeemParam.expiry
        );
        bytes32 structHash = keccak256(structData);
        bytes32 digest = _hashTypedDataV4(structHash);
        address dataSigner = ECDSAUpgradeable.recover(digest, signature);
        require(dataSigner == signerAddress, "UboxNFTStore: invalid signature");
        UboxNFT1155(redeemParam.nftAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            redeemParam.tokenId,
            redeemParam.tokenAmount,
            ""
        );
        UboxNFT1155(redeemParam.nftAddress).burn(redeemParam.tokenId, redeemParam.tokenAmount);
        if (redeemParam.refundAmount > 0) {
            bool isNativeCoin = redeemParam.currency == address(1);
            if (isNativeCoin) {
                (bool success, ) = payable(_msgSender()).call{value: redeemParam.refundAmount}("");
                require(success, "UboxNFTStore: transfer native coin failed");
            } else {
                IERC20Upgradeable(redeemParam.currency).safeTransfer(_msgSender(), redeemParam.refundAmount);
            }
        }
        emit Redeem(
            redeemParam.orderId,
            redeemParam.nftAddress,
            redeemParam.tokenId,
            redeemParam.tokenAmount,
            redeemParam.currency,
            redeemParam.refundAmount,
            _msgSender()
        );
    }

    uint256[50] private __gap;
}
