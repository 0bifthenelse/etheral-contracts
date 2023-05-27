// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "./IMain.sol";
import "./RNGQuest.sol";

contract Quest is RandomNumberGenerationQuest, UUPSUpgradeable, OwnableUpgradeable, IERC721ReceiverUpgradeable {
  /// @dev Quest logs for each player.
  struct QuestLog {
    uint256 id; // Unique ID for the quest.
    uint256 weapon_id; // Weapon token ID that is staked.
    uint256 index; // chosen quest index
    uint256 end; // end timestamp for the quest
    bytes32 status; // keccak256("ACTIVE") or keccak256("SUCCESS") or keccak256("FAILURE")
    uint256 index_text; // success or failure index to be interpretred by the frontend
  }

  /// @dev Data tracking of free quests.
  struct QuestFree {
    uint256 count; // number of free quests started per week
    uint256 date_weekly; // x free quests a week
  }

  /// @dev Rewards received by players, withdrawable.
  struct ReceivedRewards {
    uint256 as_ether;
    uint256 as_chests;
  }

  uint256 quest_count;
  QuestFree quest_free;
  uint256 quest_mul;
  IMain public MAIN;
  mapping(address => uint256) public player_quest_last_id;
  mapping(address => mapping(uint256 => QuestLog)) public quest_log;
  mapping(address => ReceivedRewards) public received_rewards;

  bool initialized;

  mapping(address => uint256) public player_quest_failed;
  mapping(address => uint256) public player_quest_succeeded;
 
  uint256[47] private __gap;

  /// @notice Initializes the smart contract.
  /// @dev Triggered on upgrades.
  /// @param main Main contract address to point to.
  function initialize(address main) initializer public {
    require(!initialized, "Already initialized.");

    __Ownable_init();

    MAIN = IMain(main);

    quest_free = QuestFree(0, block.timestamp);
    initialized = true;
  }

  event StartedQuest(uint256 indexed index, address indexed player, uint256 indexed weapon, uint128 rarity, uint256 variation);
  event StoppedQuest(uint256 id, uint256 indexed index, address indexed player);
  event CompletedQuestFailure(uint256 id, uint256 indexed index, address indexed player, uint256 indexed weapon, uint128 rarity, uint256 variation);
  event CompletedQuestSucceedChests(uint256 id, uint256 indexed index, address indexed player, uint256 indexed weapon, uint128 rarity, uint256 variation, uint256 reward);
  event CompletedQuestSucceedEther(uint256 id, uint256 indexed index, address indexed player, uint256 indexed weapon, uint128 rarity, uint256 variation, uint256 reward);

  /// @notice Changes quest rewards multiplier, up to 200%;
  /// @dev Used to adapt rewards to market analysis.
  /// @param mul New quest rewards multiplier.
  function setRewardsMul(uint256 mul) external onlyOwner payable {
    require(mul <= 200, "Rewards can't be set higher than 200%.");

    quest_mul = mul;
  }

  /// @notice Starts a quest by choosing an index. The player must have a character and have a weapon equipped.
  /// @dev Verifications are done right here, and not on startQuest from the main contract.
  /// @param index Quest index.
  function start(uint256 index) external payable {
    Player memory player = MAIN.getPlayer(_msgSender());
    Weapon memory weapon = MAIN.getWeaponEquipped(_msgSender());
    uint256 last_id = player_quest_last_id[_msgSender()];
    QuestLog storage quest = quest_log[_msgSender()][last_id];
    uint256 end = getQuestEndTime(index);
    uint256 cost = getQuestCost(index);
    uint256 days_since_weekly = (block.timestamp - quest_free.date_weekly) / 1 days;

    require(msg.value == cost, "Invalid ether value.");
    require(index < 8, "Unknown quest.");
    require(player.id != 0, "You must create a character.");
    require(player.weapon_equipped != 0, "Equip a weapon to start a quest.");
    require(player.quest_end == 0, "You are already doing a quest.");
    if (index == 0 && days_since_weekly < 7) require(quest_free.count < getQuestFreeMax(), "Free quest limit exceeded.");

    quest.id = last_id;
    quest.weapon_id = weapon.id;
    quest.index = index;
    quest.end = end;
    quest.status = keccak256("ACTIVE");
    quest_count++;

    if (index == 0) {
      if (days_since_weekly >= 7) {
        quest_free.count = 1;
        quest_free.date_weekly = block.timestamp;
      }

      else {
        quest_free.count++;
      }
    }

    MAIN.startQuest(_msgSender(), end);
    MAIN.safeTransferFrom(_msgSender(), address(this), weapon.id);

    _distributeEquity(msg.value);

    emit StartedQuest(index, _msgSender(), player.weapon_equipped, weapon.rarity, weapon.variation);
  }

  /// @notice Completes the last quest the player is doing.
  /// @dev Verifications are done right here, and not on completeQuest from the main contract.
  function complete() external {
    Player memory player = MAIN.getPlayer(_msgSender());
    Weapon memory weapon = MAIN.getWeaponEquipped(_msgSender());
    uint256 last_id = player_quest_last_id[_msgSender()];
    QuestLog storage quest = quest_log[_msgSender()][last_id];
    ReceivedRewards storage rewards = received_rewards[_msgSender()];
    (bytes32 status, uint256 index_text, bool result, bool chests) = _getQuestResult(quest.index);
    (uint256 rewards_ether, uint256 rewards_chest) = getQuestRewards(quest.index);

    require(player.quest_end != 0, "You are not running a quest.");
    require(player.quest_end <= block.timestamp, "Your quest is not finished.");

    quest.status = status;
    quest.end = 0;
    quest.index_text = index_text;
    ++player_quest_last_id[_msgSender()];

    MAIN.completeQuest(_msgSender());
    MAIN.approve(_msgSender(), quest.weapon_id);
    MAIN.safeTransferFrom(address(this), _msgSender(), quest.weapon_id);

    if (result) {
      ++player_quest_succeeded[_msgSender()];

      if ((chests && rewards_chest == 0) || (!chests && rewards_ether > 0)) { // reward is chest and rewards_chest is zero OR is a ether reward
        // then player is rewarded with ether
        rewards.as_ether += rewards_ether;

        emit CompletedQuestSucceedEther(quest.id, quest.index, _msgSender(), player.weapon_equipped, weapon.rarity, weapon.variation, rewards_ether);
      }

      else if ((!chests && rewards_ether == 0) || (chests && rewards_chest > 0)) { // reward is ether and rewards_ether is zero OR is a chest reward
        // then player is rewarded with chests
        rewards.as_chests += rewards_chest;

        emit CompletedQuestSucceedChests(quest.id, quest.index, _msgSender(), player.weapon_equipped, weapon.rarity, weapon.variation, rewards_chest);
      }

    }

    else { // quest is a failure
      rewards.as_chests += 0; 
      ++player_quest_failed[_msgSender()];

      emit CompletedQuestFailure(quest.id, quest.index, _msgSender(), player.weapon_equipped, weapon.rarity, weapon.variation);

    }
  }

  /// @notice Terminate a quest before it's complete.
  function cancel() external {
    Player memory player = MAIN.getPlayer(_msgSender());
    uint256 last_id = player_quest_last_id[_msgSender()];
    QuestLog storage quest = quest_log[_msgSender()][last_id];

    require(player.quest_end != 0, "You are not running a quest.");
    require(player.quest_end > block.timestamp, "Your quest is finished.");

    quest.status = keccak256("FAILURE");
    quest.end = 0;
    ++player_quest_last_id[_msgSender()];

    MAIN.completeQuest(_msgSender());
    MAIN.approve(_msgSender(), quest.weapon_id);
    MAIN.safeTransferFrom(address(this), _msgSender(), quest.weapon_id);

    emit StoppedQuest(quest.id, quest.index, _msgSender());
  }
 
  /// @notice Withdraw chest rewarded from quests.
  /// @dev Chests are rewarded from the main contract.
  function withdrawRewardChests() external {
    ReceivedRewards storage rewards = received_rewards[_msgSender()];
    uint256 chests = rewards.as_chests;

    require(chests > 0, "No chest rewards.");

    rewards.as_chests = 0;

    MAIN.rewardChests(_msgSender(), chests);
  }

  /// @notice Withdraw chest rewarded from quests.
  /// @dev Chests are rewarded from the main contract.
  function withdrawRewardEthers() external {
    ReceivedRewards storage rewards = received_rewards[_msgSender()];
    uint256 ethers = rewards.as_ether;

    require(ethers > 0, "No ether rewards.");

    rewards.as_ether = 0;

    payable(_msgSender()).transfer(ethers);
  }

  /// @notice Send equity from purchased chests to shareholders accordingly.
  /// @dev We ignore the returned value from send() because we don't want a shareholder to be an account that can't receive ether, as this would cause the transaction to revert.
  /// @param value Ether value to distribute.
  function _distributeEquity(uint256 value) private {
    (address[] memory shareholders, uint256[] memory percents) = MAIN.getShareholders();

    for (uint256 i = 0; i < shareholders.length; i++) {
      payable(shareholders[i]).send(MAIN.getShare(i, value));
    }
  }

  /// @notice Returns the result of a quest.
  /// @param index Quest index.
  /// @return Hashed quest status, its text index, whether it succeeded or not and whether the rewards is as ether or chests.
  function _getQuestResult(uint256 index) private returns (bytes32, uint256, bool, bool) {
    Weapon memory weapon = MAIN.getWeaponEquipped(_msgSender());
    (bytes32 status, bool result) = RandomNumberGenerationQuest.questResultStatus(index, weapon.rarity);
    (uint256 success_max, uint256 failure_max) = getQuestTextMax();
    bool chests = RandomNumberGenerationQuest.questResultRewardType();
    uint256 index_text_max;

    if (result) index_text_max = success_max;
    else index_text_max = failure_max;

    uint256 index_text = RandomNumberGenerationQuest.generateNumberWithMax(index_text_max);

    return (status, index_text, result, chests);
  }

  /// @notice Returns information of an active quest from a given user account and an id.
  /// @param id Quest ID relative to the user.
  /// @param account User account.
  /// @return All data of the active quest.
  function getQuestInfo(uint256 id, address account) external view returns (QuestLog memory) {
    return quest_log[account][id];
  }

  /// @notice Returns the last quest ID of a player.
  /// @param account User account.
  /// @return Last ID.
  function getLastQuestID(address account) external view returns (uint256) {
    return player_quest_last_id[account];
  }

  /// @notice Returns the end timestamp for a quest.
  /// @param index Quest index.
  /// @return The end timestamp for a quest given a quest index and rarity.
  function getQuestEndTime(uint256 index) public view returns (uint256) {
    uint256 duration = getQuestDuration(index);

    return duration + block.timestamp;
  }

  /// @notice Returns chest & ether rewards.
  /// @param index Quest index.
  /// @return Rewards as ether & chest.
  function getQuestRewards(uint256 index) public view returns (uint256, uint256) {
    uint256 size = 8;
    uint[] memory rewards_ether = new uint[](size);
    uint[] memory rewards_chest = new uint[](size);

    require(index < size, "R: Out of bound.");

    rewards_ether[0] = 0;
    rewards_ether[1] = 0;
    rewards_ether[2] = 200 ether; 
    rewards_ether[3] = 0; 
    rewards_ether[4] = 380 ether;
    rewards_ether[5] = 500 ether;
    rewards_ether[6] = 510 ether;
    rewards_ether[7] = 365 ether;

    rewards_chest[0] = 1;
    rewards_chest[1] = 1;
    rewards_chest[2] = 2;
    rewards_chest[3] = 2;
    rewards_chest[4] = 3;
    rewards_chest[5] = 4;
    rewards_chest[6] = 5;
    rewards_chest[7] = 5;

    return (rewards_ether[index] * quest_mul / 100, rewards_chest[index] * quest_mul / 100);
  }

  /// @notice Returns quest cost as ether given an index.
  /// @param index Quest index.
  /// @return Quest as ether.
  function getQuestCost(uint256 index) public pure returns (uint256) {
    uint256 size = 8;
    uint[] memory cost = new uint[](size);

    require(index < size, "Q: Out of bound.");

    cost[0] = 0;
    cost[1] = 60 ether;
    cost[2] = 5 ether;
    cost[3] = 35 ether;
    cost[4] = 40 ether;
    cost[5] = 40 ether;
    cost[6] = 90 ether;
    cost[7] = 75 ether;

    return cost[index];
  }

  /// @notice Returns quest duration given an index.
  /// @param index Quest index.
  /// @return Quest duration as a unix timestamp.
  function getQuestDuration(uint256 index) public pure returns (uint256) {
    uint256 size = 8;
    uint[] memory duration = new uint[](size);

    require(index < size, "D: Out of bound.");

    duration[0] = 1 days;
    duration[1] = 2 days;
    duration[2] = 4 days;
    duration[3] = 6 days;
    duration[4] = 8 days;
    duration[5] = 12 days;
    duration[6] = 14 days;
    duration[7] = 16 days;

    return duration[index];
  }

  /// @notice Returns the maximum index of text for failure or success.
  /// @return Success & Failure max indexes.
  function getQuestTextMax() public pure returns (uint256, uint256) {
    return (24, 24);
  }

  /// @notice Returns whether the given quest is active or not..
  /// @param id Quest ID relative to the user.
  /// @param account User account.
  /// @return Active (true) or not (false).
  function getQuestActive(uint256 id, address account) public view returns (bool) {
    return quest_log[account][id].status == keccak256("ACTIVE");
  }

  /// @notice Returns whether the given quest is a success or failure.
  /// @dev (false, false) => Failure
  /// @dev (false, true) => Active
  /// @dev (true, false) => Success
  /// @dev (false, false) can also be returned if the quest doesn't exist.
  /// @param id Quest ID relative to the user.
  /// @param account User account.
  /// @return Success (true) or failure (false), second returned value is whether it's active or not.
  function getQuestSuccessOrFailure(uint256 id, address account) public view returns (bool, bool) {
    return (quest_log[account][id].status == keccak256("SUCCESS"), getQuestActive(id, account));
  }

  /// @notice Returns the maximum number of started free quests per week.
  /// @return Amount of free quests a week.
  function getQuestFreeMax() public pure returns (uint256) {
    return 20;
  }

  /// @notice Returns the number of free quests remaining.
  /// @return Amount of free quests remaining.
  function getQuestFreeRemaining() public view returns (uint256) {
    return getQuestFreeMax() - quest_free.count;
  }

  /// @notice Returns the freee quest weekly timestamp.
  /// @return Weekly timestamp, refreshed every week.
  function getQuestFreeWeekLast() public view returns (uint256) {
    return quest_free.date_weekly;
  }

  /// @notice Upgrading the contract allows us to keep building, improving and expanding the game.
  /// @dev This allows upgrade of the contract.
  /// @param implementation New implementation address.
  function _authorizeUpgrade(address implementation) internal onlyOwner override {}

  /// @notice Adds support for receiving NFTs, required for the staking mechanism.
  /// @param _operator Operator of the token.
  /// @param _from Token sender..
  /// @param _tokenId Token ID.
  /// @param _data Transaction data..
  function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) public returns (bytes4) {
    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }
}
