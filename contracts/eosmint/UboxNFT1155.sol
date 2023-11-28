// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract UboxNFT1155 is ERC1155, Ownable2Step {
    using Strings for uint256;
    string public name;
    string public symbol;
    string baseURI;
    address public operator;
    mapping(uint256 => uint256) public tokenMaxSupply;
    mapping(uint256 => uint256) public tokenMinted;
    mapping(uint256 => uint256) public tokenBurnt;

    event SetOperator(address indexed operator);
    event SetBaseURI(string baseUri);
    event SetMaxSupply(uint256 indexed tokenId, uint256 indexed maxSupply);

    modifier onlyOperator() {
        require(operator == _msgSender(), "NFT: caller is not the operator");
        _;
    }

    constructor(string memory _name, string memory _symbol, string memory _baseUri) ERC1155("") {
        name = _name;
        symbol = _symbol;
        baseURI = _baseUri;
    }

    function renounceOwnership() public virtual override onlyOwner {
        revert("NFT: renounce ownership is not allowed");
    }

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "NFT: operator can not be address(0)");
        operator = _operator;
        emit SetOperator(operator);
    }

    function setBaseURI(string memory _baseUri) external onlyOwner {
        require(bytes(_baseUri).length > 0, "NFT: baseUri can not be empty");
        baseURI = _baseUri;
        emit SetBaseURI(baseURI);
    }

    function setMaxSupply(uint256 _tokenId, uint256 _maxSupply) external onlyOperator {
        require(_maxSupply > 0, "NFT: max supply must be greater than 0");
        tokenMaxSupply[_tokenId] = _maxSupply;
        emit SetMaxSupply(_tokenId, _maxSupply);
    }

    function mint(address _to, uint256 _id, uint256 _amount) external onlyOperator {
        require(tokenMaxSupply[_id] > 0, "NFT: token id does not exist");
        require(_amount > 0, "NFT: amount must be greater than 0");
        require(tokenMinted[_id] + _amount <= tokenMaxSupply[_id], "NFT: can not exceed the max supply");
        _mint(_to, _id, _amount, "");
        tokenMinted[_id] = tokenMinted[_id] + _amount;
    }

    function burn(uint256 _id, uint256 _amount) external onlyOperator {
        require(tokenMaxSupply[_id] > 0, "NFT: token id does not exist");
        require(_amount > 0, "NFT: amount must be greater than 0");
        _burn(msg.sender, _id, _amount);
        tokenBurnt[_id] = tokenBurnt[_id] + _amount;
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(tokenMaxSupply[_id] > 0, "NFT: token id does not exist");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _id.toString())) : "";
    }

    function totalMint(uint256 _id) public view returns (uint256, uint256) {
        return (tokenMinted[_id], tokenMaxSupply[_id]);
    }

    function totalSupply(uint256 _id) public view returns (uint256) {
        return tokenMinted[_id] - tokenBurnt[_id];
    }
}
