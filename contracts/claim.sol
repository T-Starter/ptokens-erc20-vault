contract Verify {

    function recoverSigner(bytes32 message, bytes memory sig)
    public
    pure
    returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        if (v != 27 && v != 28) {
            return (address(0));
        } else {
            // solium-disable-next-line arg-overflow
            return ecrecover(message, v, r, s);
        }
    }

    function splitSignature(bytes memory sig)
    public
    pure
    returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
        // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
        // second 32 bytes
            s := mload(add(sig, 64))
        // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27)
            v += 27;

        return (v, r, s);
    }
}


library Endian {
    /* https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32 */
    function reverse64(uint64 input) internal pure returns (uint64 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
        ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
        ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
    }
    function reverse32(uint32 input) internal pure returns (uint32 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00) >> 8) |
        ((v & 0x00FF00FF) << 8);

        // swap 2-byte long pairs
        v = (v >> 16) | (v << 16);
    }
    function reverse16(uint16 input) internal pure returns (uint16 v) {
        v = input;

        // swap bytes
        v = (v >> 8) | (v << 8);
    }
}

// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
}



    function verifySigData(bytes memory sigData) private returns (TeleportData memory) {
        TeleportData memory td;

        uint64 id;
        uint32 ts;
        uint64 fromAddr;
        uint64 quantity;
        uint64 symbolRaw;
        uint8 chainId;
        address toAddress;
        address tokenAddress;
        uint64 requiredSymbolRaw;

        assembly {
            id := mload(add(add(sigData, 0x8), 0))
            ts := mload(add(add(sigData, 0x4), 8))
            fromAddr := mload(add(add(sigData, 0x8), 12))
            quantity := mload(add(add(sigData, 0x8), 20))
            symbolRaw := mload(add(add(sigData, 0x8), 29))
            chainId := mload(add(add(sigData, 0x1), 36))
            tokenAddress := mload(add(add(sigData, 0x14), 37))
            toAddress := mload(add(add(sigData, 0x14), 51))
        }
        td.id = Endian.reverse64(id);
        td.ts = Endian.reverse32(ts);
        td.fromAddr = Endian.reverse64(fromAddr);
        td.quantity = Endian.reverse64(quantity);
        td.symbolRaw = Endian.reverse64(symbolRaw);
        td.chainId = chainId;
        td.tokenAddress = tokenAddress;
        td.toAddress = toAddress;

        requiredSymbolRaw = uint64(bytes8(stringToBytes32(TeleportToken.symbol)));
        require(requiredSymbolRaw == symbolRaw-td.chainId, "Wrong symbol");
        require(thisChainId == td.chainId, "Invalid Chain ID");
        require(block.timestamp < SafeMath.add(td.ts, (60 * 60 * 24 * 30)), "Teleport has expired");
        require(!claimed[td.id], "Already Claimed");

        claimed[td.id] = true;

        return td;
    }

        function claim(bytes memory sigData, bytes[] calldata signatures) public returns (address toAddress) {
            TeleportData memory td = verifySigData(sigData);

            // verify signatures
            require(sigData.length == 69, "Signature data is the wrong size");
            require(signatures.length <= 10, "Maximum of 10 signatures can be provided");

            bytes32 message = keccak256(sigData);

            uint8 numberSigs = 0;

            for (uint8 i = 0; i < signatures.length; i++){
                address potential = Verify.recoverSigner(message, signatures[i]);

                // console.log(potential);
                // console.log(oracles[potential]);
                // console.log(!signed[td.id][potential]);
                // Check that they are an oracle and they haven't signed twice
                if (oracles[potential] && !signed[td.id][potential]){
                    signed[td.id][potential] = true;
                    numberSigs++;

                    if (numberSigs >= threshold){
                        break;
                    }
                }
            }

            require(numberSigs >= threshold, "Not enough valid signatures provided");

//            balances[address(0)] = balances[address(0)].sub(td.quantity);
//            balances[td.toAddress] = balances[td.toAddress].add(td.quantity);

            emit Claimed(td.id, td.toAddress, td.quantity);

            return pegOut(td.toAddress, td.tokenAddress, td.quantity);

            //            emit Transfer(address(0), td.toAddress, td.quantity);

//            return td.toAddress;
        }
