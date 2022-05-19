// SPDX-License-Identifier: MIT

// NOTE: cloned from sushiswap code at canary #45da9720

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SingleChef is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of tokens entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    uint128 public accTokenPerShare;
    uint64 public lastRewardTime;
    uint32 public stopAtTime = 2**32-1;

    /// @notice Address of TOKEN contract.
    IERC20 public TOKEN;

    address public custodian;

    /// @notice Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;

    uint256 public tokenPerSecond;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdatePool(uint64 lastRewardTime, uint256 lpSupply, uint256 accTokenPerShare);
    event LogTokenPerSecond(uint256 tokenPerSecond);

    /// @param token The TOKEN token contract address.
    constructor(IERC20 token, address _custodian) {
        TOKEN = token;
        custodian = _custodian;
    }

    function setCustodian(address _custodian) public onlyOwner {
        custodian = _custodian;
    }

    function setStopAtTime(uint32 _stopAtTime) public onlyOwner {
        stopAtTime = _stopAtTime;
    }

    /// @notice Sets the token per second to be distributed. Can only be called by the owner.
    /// @param _tokenPerSecond The amount of Token to be distributed per second.
    function setTokenPerSecond(uint256 _tokenPerSecond) public onlyOwner {
        tokenPerSecond = _tokenPerSecond;
        emit LogTokenPerSecond(_tokenPerSecond);
    }

    function endTimestamp() internal view returns (uint32) {
        return block.timestamp > stopAtTime ? stopAtTime : uint32(block.timestamp);
    }

    /// @notice View function to see pending TOKEN on frontend.
    /// @param _user Address of user.
    /// @return pending TOKEN reward for a given user.
    function pendingToken(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = TOKEN.balanceOf(address(this));

        uint256 _accTokenPerShare = accTokenPerShare;

        uint256 _endTimestamp = endTimestamp();

        if (_endTimestamp > lastRewardTime && lpSupply != 0) {
            uint256 time = _endTimestamp - lastRewardTime;
            uint256 tokenReward = time * tokenPerSecond;
            _accTokenPerShare += uint256(tokenReward * ACC_TOKEN_PRECISION / lpSupply);
        }

        int256 _pending = int256(user.amount * _accTokenPerShare / ACC_TOKEN_PRECISION) - user.rewardDebt;
        require(_pending >= 0, "underflow");

        pending = uint256(_pending);
    }

    /// @notice Update reward variables of the given pool.
    function updatePool() public {
        uint256 _endTimestamp = endTimestamp();

        if (_endTimestamp > lastRewardTime) {
            uint256 lpSupply = TOKEN.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 time = _endTimestamp - lastRewardTime;
                uint256 tokenReward = time * tokenPerSecond;
                accTokenPerShare += uint128(tokenReward * ACC_TOKEN_PRECISION / lpSupply);
            }
            lastRewardTime = uint64(block.timestamp);
            emit LogUpdatePool(lastRewardTime, lpSupply, accTokenPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCV2 for TOKEN allocation.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 amount, address to) public {
        updatePool();
        UserInfo storage user = userInfo[to];

        // Effects
        user.amount += amount;
        user.rewardDebt += int256(amount * accTokenPerShare / ACC_TOKEN_PRECISION);

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, to);
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 amount, address to) public {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];

        // Effects
        user.rewardDebt -= int256(amount * accTokenPerShare / ACC_TOKEN_PRECISION);
        user.amount -= amount;

        TOKEN.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param to Receiver of TOKEN rewards.
    function harvest(address to) public {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = int256(user.amount * accTokenPerShare / ACC_TOKEN_PRECISION);

        require(accumulatedToken - user.rewardDebt >= 0, "underflow");
        uint256 _pendingToken = uint256(accumulatedToken - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedToken;

        // Interactions
        if (_pendingToken != 0) {
            TOKEN.safeTransferFrom(custodian, to, _pendingToken);
        }

        emit Harvest(msg.sender, _pendingToken);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and TOKEN rewards.
    function withdrawAndHarvest(uint256 amount, address to) public {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = int256(user.amount * accTokenPerShare / ACC_TOKEN_PRECISION);

        require(accumulatedToken - user.rewardDebt >= 0, "underflow");
        uint256 _pendingToken = uint256(accumulatedToken - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedToken - int256(amount * accTokenPerShare / ACC_TOKEN_PRECISION);
        user.amount -= amount;

        // Interactions
        if (_pendingToken > 0) {
            TOKEN.safeTransferFrom(custodian, to, _pendingToken);
        }

        TOKEN.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
        emit Harvest(msg.sender, _pendingToken);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(address to) public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        TOKEN.safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, amount, to);
    }
}
