// Copyright (C) 2019 David Terry <me@xwvvvvwx.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0 <0.6.0;

contract DSPause {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) public auth { wards[guy] = 1; }
    function deny(address guy) public auth { wards[guy] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- Data ---
    struct Execution {
        address  guy;
        bytes    data;
        uint256  timestamp;
    }

    mapping (bytes32 => Execution) public queue;
    uint public delay;
    uint public freezeUntil;

    // --- Init ---
    constructor(uint delay_) public {
        wards[msg.sender] = 1;
        delay = delay_;
        freezeUntil = 0;
    }

    // --- Logic ---
    function schedule(address guy, bytes memory data) public auth returns (bytes32 id) {
        require(now > freezeUntil);
        require(guy != address(0));

        id = keccak256(abi.encode(guy, data, now));

        Execution storage entry = queue[id];
        entry.guy = guy;
        entry.data = data;
        entry.timestamp = now;

        return id;
    }

    function cancel(bytes32 id) public auth {
        require(now > freezeUntil);
        delete queue[id];
    }

    function execute(bytes32 id) public payable returns (bytes memory response) {
        require(now > freezeUntil);

        Execution memory entry = queue[id];
        require(now > entry.timestamp + delay);

        require(entry.guy != address(0));
        delete queue[id];

        address target = entry.guy;
        bytes memory data = entry.data;

        // call contract in current context
        assembly {
            let succeeded := delegatecall(sub(gas, 5000), target, add(data, 0x20), mload(data), 0, 0)
            let size := returndatasize

            response := mload(0x40)
            mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                revert(add(response, 0x20), size)
            }
        }
    }

    function freeze(uint256 timestamp) public auth {
        freezeUntil = timestamp;
    }
}