/*
This file is part of the NFT Protect project <https://nftprotect.app/>

The UserRegistry Contract is free software: you can redistribute it and/or
modify it under the terms of the GNU lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The UserRegistry Contract is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU lesser General Public License for more details.

You should have received a copy of the GNU lesser General Public License
along with the UserRegistry Contract. If not, see <http://www.gnu.org/licenses/>.

@author Ilya Svirin <is.svirin@gmail.com>
*/
// SPDX-License-Identifier: GNU lesser General Public License


pragma solidity ^0.8.0;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";
import "github.com/kleros/erc-792/blob/v8.0.0/contracts/IArbitrator.sol";
import "github.com/kleros/erc-792/blob/v8.0.0/contracts/IArbitrable.sol";
import "./iuserregistry.sol";
import "./iuserdid.sol";


contract UserRegistry is Ownable, IArbitrable, IUserRegistry
{
    event Deployed();
    event ArbitratorChanged(address arbitrator);
    event DIDRegistered(address indexed did, string provider);
    event DIDUnregistered(address indexed did);
    event SuccessorRequested(uint256 indexed disputeId, address indexed user, address indexed successor, bytes extraData);
    event SuccessorAppealed(uint256 indexed disputeId, bytes extraData);
    event SuccessorApproved(uint256 indexed disputeId);
    event SuccessorRejected(uint256 indexed disputeId);

    IArbitrator public   arbitrator;
    IUserDID[]  public   dids;
    uint256     constant numberOfRulingOptions = 2; // Notice that option 0 is reserved for RefusedToArbitrate

    mapping(address => address) public successors;

    struct SuccessorRequest
    {
        address user;
        address successor;
    }
    mapping(uint256 => SuccessorRequest) public disputes;

    constructor(IArbitrator arb, IUserDID did)
    {
        emit Deployed();
        setArbitrator(arb);
        registerDID(did);
    }
    
    function setArbitrator(IArbitrator arb) public onlyOwner
    {
        arbitrator = arb;
        emit ArbitratorChanged(address(arb));
    }

    function registerDID(IUserDID did) public onlyOwner
    {
        dids.push(did);
        emit DIDRegistered(address(did), did.provider());
    }

    function unregisterDID(IUserDID did) public onlyOwner
    {
        for(uint256 i = 0; i < dids.length; ++i)
        {
            if(dids[i] == did)
            {
                dids[i] = dids[dids.length - 1];
                dids.pop();
                emit DIDUnregistered(address(did));
                break;
            }
        }
    }

    function isRegistered(address user) public view override returns(bool)
    {
        for(uint256 i = 0; i < dids.length; ++i)
        {
            if(dids[i].isIdentified(user))
            {
                return true;
            }
        }
        return false;
    }

    function scores(address user) public view override returns(uint256)
    {
        uint256 scoresMax = 0;
        for(uint256 i = 0; i < dids.length; ++i)
        {
            uint256 scoresCur = dids[i].scores(user);
            if(scoresCur > scoresMax)
            {
                scoresMax = scoresCur;
            }
        }
        return scoresMax;
    }

    function isSuccessor(address user, address successor) public view override returns(bool)
    {
        return successors[user] == successor;
    }

    function hasSuccessor(address user) public view override returns(bool)
    {
        return successors[user] != address(0);
    }

    function successorOf(address user) external view override returns(address)
    {
        return successors[user];
    }

    function successorRequest(address user, bytes calldata extraData) public payable returns(uint256)
    {
        require(isRegistered(user), "UserRegistry: Unregistered user");
        uint256 disputeId = arbitrator.createDispute{value: msg.value}(numberOfRulingOptions, extraData);
        disputes[disputeId] = SuccessorRequest(user, _msgSender());
        emit SuccessorRequested(disputeId, user, _msgSender(), extraData);
        return disputeId;
    }

    function successorRequestAppeal(uint256 disputeId, bytes calldata extraData) public payable
    {
        require(disputes[disputeId].successor == _msgSender(), "UserRegistry: not the owner of the request");
        arbitrator.appeal{value: msg.value}(disputeId, extraData);
        emit SuccessorAppealed(disputeId, extraData);
    }

    function rule(uint256 disputeId, uint256 ruling) external override
    {
        require(_msgSender() == address(arbitrator), "UserRegistry: not the arbitrator");
        require(ruling <= numberOfRulingOptions, "UserRegistry: invalid ruling");
        SuccessorRequest memory request = disputes[disputeId];
        if (ruling == 1)
        {
            successors[request.user] = request.successor;
            emit SuccessorApproved(disputeId);
        }
        else
        {
            emit SuccessorRejected(disputeId);
        }
        delete disputes[disputeId];
    }
}
