// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./RNGMain.sol";

/// @dev Extiint & Apeiron
/// @title Main contract (Weapon NFT & a few states)
contract Main is RandomNumberGenerationMain, UUPSUpgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable {
  struct Weapon {
    uint256 id; // token ID of the weapon.
    uint128 rarity; // weapon rarity from 1 to 9.
    uint256 variation; // weapon variation (sword, staff, great axe, ...)
    bool destroyed; // whether it is destroyed or not.
  }

  struct Player {
    uint256 id; // player character ID.
    uint256 chests; // number of chests owned.
    uint256 weapon_equipped; // weapon id of the equipped weapon, 0 if no weapon equipped.
    uint256 quest_end; // timestamp of a quest end, 0 if no active quest.
  }

  uint256 public supply;
  address public QUEST;
  address public ROYALTY_RECEIVER;
  mapping(address => Player) public players;
  mapping(uint256 => Weapon) public weapons;

  uint256 private constant ROYALTY = 5;
  uint256 private constant PERCENT_DIVIDER = 10;
  uint256 private token_id;

  uint256[50] private __gap;

  modifier onlyQuest() {
    require(_msgSender() == QUEST, "Only from quest contract.");
    _;
  }

  /// @notice Initializes the smart contract, is triggered only once on proxy deployment
  function initialize(address royalty_receiver) initializer public {
    __ERC721_init("Weapons", "WPN");
    __Ownable_init();

    ROYALTY_RECEIVER = royalty_receiver;
  }

  event WeaponUpgraded(
    address indexed owner,
    uint256 indexed id,
    uint256 newId
  );
  event WeaponDestroyed(address indexed owner, uint256 indexed id, uint256 newId);
  event CharacterCreated(address indexed player, uint256 indexed id);
  event PurchasedChests(address indexed player, uint256 indexed count);
  event OpenedChest(address indexed player);

  /// @notice Changes the Quest contract address.
  /// @param quest New quest contract address.
  function setQuest(address quest) external onlyOwner {
    QUEST = quest;
  }

  /// @notice Changes royalty receiver, which receives royalties from trades on NFT marketplaces.
  /// @param receiver New royalty receiver.
  function setRoyaltyReceiver(address receiver) external onlyOwner {
    require(receiver != ROYALTY_RECEIVER, "No change in receiver.");

    ROYALTY_RECEIVER = receiver;
  }

  /// @notice Mint a weapon from any rarity and variation, bypassing RNG.
  /// @dev This is intended for testnet ONLY.
  /// @param rarity Weapon rarity.
  /// @param variation Weapon variation.
  function mintWeaponAny(uint128 rarity, uint256 variation) external onlyOwner {
    Weapon storage weapon = weapons[++token_id];
    Player storage player = players[_msgSender()];

    require(rarity < 10, "Invalid weapon rarity.");
    require(variation < 5, "Invalid weapon variation.");

    weapon.id = token_id;
    weapon.rarity = rarity;
    weapon.variation = variation;

    _mint(_msgSender(), token_id);
  }

  /// @notice Purchases a chest. Chests can also be given as a reward.
  /// @dev To buy a chest, the user must own a character first.
  function buyChests() external payable {
    Player storage player = players[_msgSender()];
    (uint256 cost_chest,) = getCosts();
    uint256 count = msg.value / cost_chest;

    require(player.id != 0, "You need to own a character.");
    require(msg.value / cost_chest >= 1, "One chest minimum.");

    player.chests += count;

    _distributeEquity(msg.value);

    emit PurchasedChests(_msgSender(), count);
  }

  /// @notice Mints a new weapon by using one chest.
  /// @dev Can't be send to an account that does not support ERC721 interface.
  function openChest() external {
    uint128 rarity = RandomNumberGenerationMain.weaponMintRarity();
    uint256 variation = RandomNumberGenerationMain.weaponMintVariation();
    Weapon storage weapon = weapons[++token_id];
    Player storage player = players[_msgSender()];

    require(player.chests > 0, "You need chests to mint weapons.");
    require(supply < getMaxSupply(), "Max supply reached.");

    weapon.id = token_id;
    weapon.rarity = rarity;
    weapon.variation = variation;
    player.chests--;
    supply++;

    _mint(_msgSender(), token_id);

    emit OpenedChest(_msgSender());
  }

  /// @notice Upgrade a weapon. If the upgrade fails, the weapon is destroyed.
  /// @dev Weapon rarity increase or is burned.
  /// @param id ID of the weapon to upgrade.
  function upgradeWeapon(uint256 id) external payable {
    Weapon storage weapon = weapons[id];
    Weapon storage weapon_new = weapons[++token_id];
    bool success = RandomNumberGenerationMain.weaponUpgradeAllowedOrFail(weapon.rarity); 
    (,uint256 cost_upgrade) = getCosts();

    require(_exists(id), "This weapon does not exist.");
    require(msg.value == cost_upgrade, "Incorrect upgrade value.");
    require(ownerOf(id) == _msgSender(), "You do not own this weapon.");
    require(weapon.rarity >= 1 && weapon.rarity <= 8, "Can't upgrade this weapon.");

    _burn(id);

    weapon.destroyed = true;

    if (success) {
      _mint(_msgSender(), token_id); // mints the newly upgraded weapon

      weapon_new.rarity = weapon.rarity + 1;
      weapon_new.id = token_id;
      weapon_new.variation = weapon.variation;


      emit WeaponUpgraded(_msgSender(), id, weapon_new.id);
    } else {
      --supply;

      _mint(_msgSender(), token_id); // mints the new broken piece

      weapon_new.rarity = weapon.rarity;
      weapon_new.id = token_id;
      weapon_new.variation = 0; // variation 0 are reserved to broken pieces


      emit WeaponDestroyed(_msgSender(), id, weapon_new.id);
    }

    _distributeEquity(msg.value);
  }

  /// @notice Creates a free character and get a free wooden sword. Gives a free character and a non NFT wooden sword to play with.
  /// @dev Checks if the player has a character (player character ID is not zero), then checks if the given ID is valid, only then mutators are triggered and state are changed.
  /// @param id Character ID.
  function newPlayer(uint256 id) external {
    Player storage player = players[_msgSender()];
    Weapon storage weapon = weapons[++token_id];
    uint256 variation = RandomNumberGenerationMain.weaponMintVariation();

    require(player.id == 0, "You already have a character.");
    require(id > 0 && id <= 4, "Invalid character ID."); // character ID in [1, 4]

    player.id = id;
    weapon.id = token_id;
    weapon.variation = variation;

    _mint(_msgSender(), token_id); // free weapons are not counted on the total supply

    emit CharacterCreated(_msgSender(), id);
  }

  /// @notice Equip a weapon the player owns.
  /// @dev Equipping a weapon is necessary to engage in a quest.
  /// @param id Weapon ID.
  function equipWeapon(uint256 id) external {
    Player storage player = players[_msgSender()];
    Weapon storage weapon = weapons[id];

    require(weapon.variation != 0, "You can't equip a broken piece.");
    require(ownerOf(id) == _msgSender(), "Not your weapon.");
    require(player.id != 0, "You need to select a character.");
    require(!(player.weapon_equipped == id), "You already hold this weapon.");
    require(player.quest_end == 0, "You are doing a quest.");

    player.weapon_equipped = id;
  }

  /// @notice Starts a quest, triggered from quest contract to modify player quest end timestamp.
  /// @dev Verifications are done on the quest contract.
  /// @param _player Player account address.
  /// @param end Quest end timestamp.
  function startQuest(address _player, uint256 end) external onlyQuest {
    Player storage player = players[_player];

    player.quest_end = end;
  }

  /// @notice Completes a quest, triggered from quest contract to modify player quest end timestamp.
  /// @dev Verifications are done on the quest contract.
  /// @param _player Player account address.
  function completeQuest(address _player) external onlyQuest {
    Player storage player = players[_player];

    player.quest_end = 0;
  }

  /// @notice Receives rewards as chests.
  /// @dev Verifications are done on the quest contract.
  /// @param _player Player account address.
  function rewardChests(address _player, uint256 rewarded_chests) external onlyQuest {
    Player storage player = players[_player];

    player.chests += rewarded_chests;
  }

  /// @notice Send equity from purchased chests to shareholders accordingly.
  /// @dev We ignore the returned value from send() because we don't want a shareholder to be an account that can't receive ether, as this would cause the transaction to revert.
  /// @param value Ether value to distribute.
  function _distributeEquity(uint256 value) private {
    (address[] memory shareholders, uint256[] memory percents) = getShareholders();

    for (uint256 i = 0; i < shareholders.length; i++) {
      payable(shareholders[i]).send(getShare(i, value));
    }
  }

  /// @notice Returns an array of all shareholders, associated to a second array that matches each shareholder's percentage.
  /// @dev Percentages are multiplied by PERCENT_DIVIDER, and if the total sum of percentages goes beyond 100%, then it reverts, to prevent exploit.
  /// @return shareholders Array of all shareholders.
  /// @return percents Array of associated shareholder percent.
  function getShareholders() public pure returns (address[] memory shareholders, uint256[] memory percents) {
    uint256 percents_sum = 0;
    shareholders = new address[](4);
    percents = new uint256[](4);

    shareholders[0] = address(0x0); // treasury
    shareholders[1] = address(0x0); // team
    shareholders[2] = address(0x0); // investors
    shareholders[3] = address(0x0); // partners

    percents[0] = 350; // treasury
    percents[1] = 350; // team
    percents[2] = 200; // investors
    percents[3] = 100; // partners

    for (uint256 i = 0; i < percents.length; i++) {
      percents_sum += percents[i];
    }

    if (percents_sum > 100 * PERCENT_DIVIDER)
      revert("Incorrect share percent sum.");
  }

  /// @notice Returns an amount modified to match the share percentage of a given shareholder.
  /// @param shareholder Shareholder index to use based on {_getShareholders}.
  /// @param amount Amount to modify. Royalties is a low number while mints are 100%.
  /// @return Amount reduced by the shareholder's percentage.
  function getShare(uint256 shareholder, uint256 amount) public pure returns (uint256) {
    (address[] memory shareholders, uint256[] memory percents ) = getShareholders();

    require(shareholder < shareholders.length, "Out of bound shareholder index.");

    return (amount * percents[shareholder]) / PERCENT_DIVIDER;
  }

  /// @notice Returns all weapons owned by the player, and ignores broken pieces (variation 0)
  /// @dev We keep track of the number of elements added in weapons_owned then remove any unused slots.
  /// @param player Player to get its weapon owned.
  /// @return weapons_owned Array of owned weapons by the player.
  function getWeaponsOwned(address player) external view returns (Weapon[] memory weapons_owned) {
    uint256 max_index = balanceOf(player);

    weapons_owned = new Weapon[](max_index);

    for (uint256 i = 0; i < max_index; i++) {
      weapons_owned[i] = weapons[tokenOfOwnerByIndex(player, i)];
    }
  }

  /// @notice Returns the owner of a weapon given an ID.
  /// @param id Weapon ID.
  /// @return Account address of the owner.
  function getWeaponOwner(uint256 id) external view returns (address) {
    return ownerOf(id);
  }

  /// @notice Returns the existence of the given weapon ID.
  /// @dev This is used to verify whether a weapon has been destroyed or do not exist.
  /// @param id Weapon ID.
  /// @return Exists or not.
  function getWeaponExistence(uint256 id) external view returns (bool) {
    return _exists(id);
  }

  /// @notice Returns the rarity of the given weapon.
  /// @param id Weapon ID.
  /// @return Weapon rarity from 0 to 9.
  function getWeaponRarity(uint256 id) external view returns (uint128) {
    return weapons[id].rarity;
  }

  /// @notice Returns the weapon the player owns.
  /// @dev Having a weapon equipped allows quests.
  /// @param player Player account.
  /// @return Weapon structure of the weapon the player character is equipped.
  function getWeaponEquipped(address player) external view returns (Weapon memory) {
    return weapons[players[player].weapon_equipped];
  }

  /// @notice Returns the player from a given address.
  /// @param player Player account address.
  /// @return The player.
  function getPlayer(address player) external view returns (Player memory) {
    return players[player];
  }

  /// @notice Returns a player given a token ID.
  /// @param id Weapon token ID.
  /// @return The weapon.
  function getWeapon(uint256 id) external view returns (Weapon memory) {
    return weapons[id];
  }

  /// @notice Returns costs to purchase chest or execute weapon upgrades.
  /// @return (chest, upgrade) Chest purchase cost & weapon upgrade cost.
  function getCosts() public pure returns (uint256, uint256) {
    uint256 cost_chest = 0.00005 ether;
    uint256 cost_upgrade = 0.001 ether;

    return (cost_chest, cost_upgrade);
  }

  /// @notice Returns the maximum supply of weapons.
  /// @return The max supply.
  function getMaxSupply() public pure returns (uint256) {
    return uint256(10_000);
  }

  /// @notice Upgrading the contract allows us to keep building, improving and expanding the game.
  /// @dev This allows upgrade of the contract, only by ownership.
  /// @param implementation New implementation address.
  function _authorizeUpgrade(address implementation) internal onlyOwner override {}
  /// @notice Returns whether the given interface ID is supported by this smart contract.
  /// @dev ERC721 & ERC2981 are the only supported interfaces.
  /// @param interfaceId Interface ID to check whether if it is supported.
  /// @return True or false depending on whether the given interface ID is supported.
  function supportsInterface(bytes4 interfaceId)
  public
  view
  override
  returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  /// @notice Overrides function triggered before a token transfer.
  /// @dev Allows token transfers but also prevents soulbound token from being transferred.
  /// @param from Account address to send from.
  /// @param to Account address to send to.
  /// @param tokenId Weapon ID to transfer.
  /// @param batchSize Batch size (higher than 1 is a mint attempt).
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal override {
    Player memory player = players[_msgSender()];
    Weapon memory weapon = weapons[tokenId];

    require(weapon.variation != 0 || from == address(0x0), "Broken pieces are soulbound.");
    require(from == address(0x0) || to == address(0x0) || to == address(QUEST) || from == address(QUEST), "Weapon can't be transferred.");
    require(from == address(0x0) || !(player.weapon_equipped == tokenId) || to == address(QUEST) || from == address(QUEST), "Weapon is currently equipped.");

    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  /// @notice Description for the end user.
  /// @dev Description for a developer or auditor.
  /// @return recipients Royalties recipients to return.
  /// @return royalties Royalties percentages to return.
  function royaltyInfo(uint256 tokenId, uint256 salePrice) public view returns (address, uint256) {
    return (ROYALTY_RECEIVER, (salePrice * ROYALTY) / 100);
  }

  /// @notice Returns the URI of a weapon given its rarity.
  /// @dev Weapon variation are equals to character classes, in that variation 1 = sword = warrior..
  /// @param tokenId ID of the weapon token.
  /// @return URI of the given token.
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    uint256 size = 10;
    string[] memory uri_weapons = new string[](size);
    uint128 rarity = weapons[tokenId].rarity;
    uint256 variation = weapons[tokenId].variation;

    require(rarity < size, "Out of bound.");

    if (variation == 0) return "QmZZG7wsGqWXwWuAc4rUbyzztefRKxkFZbEzhrEpboba2r"; // broken pieces are variation 0

    else if (variation == 1) { // sword variation
      uri_weapons[0] = "QmUV2ytoU5KLqPfATTH7jj4ZABJb4GcLpqrZhKt9w7hsz6";
      uri_weapons[1] = "QmZi6BVD6zXEzo1TmNEJkJFpgzZidi4rc2rB35LNDLkaq3";
      uri_weapons[2] = "QmVcxr9UCHDi3aaKJJzDdmTmuEsDv3xV5cLv18C9oQMmUM";
      uri_weapons[3] = "QmeFqgBJqDwzMj8KtbtnPbUVWZWLNooxZDcFWHVKCmt2yZ";
      uri_weapons[4] = "QmdyixWcBwjSbgA6tTa5hKzrkCEgP22XiF2RT36wfszC9k";
      uri_weapons[5] = "QmNLf5T3udFMHyh3NRPayrwcDeWgeEcfo4csYeBwunCySf";
      uri_weapons[6] = "QmWZukULqXnPZ1Giau5yosVTxLs2Xs2XfnCfQkZKosdVNW";
      uri_weapons[7] = "Qmdi7T3F158YRNC3rGBSRvjpYjzekhZUPhe3hvASGZgQre";
      uri_weapons[8] = "QmciNmd7UcUWbyE4MG8JWGBTEqEC1ZoUZzqndDqhyxTGjX";
      uri_weapons[9] = "QmWvuzicrEoHS8822yjE8gu6FmeRG6Pkq2BVy7CbEyh58W";
    }

    else if (variation == 2) { // dagger variation
      uri_weapons[0] = "QmVi74xfj4tS1UHXhLwd2JU5z3ax7YRFmPfYc5r2VaxitL";
      uri_weapons[1] = "Qmc7GAwXd8jw7gRM5SNB7vuFqfupdEZ1DgYcBqQd4qb9DJ";
      uri_weapons[2] = "QmXTfSD3wgWNVEKLJQPEiRtbV7KR5o3hkvjyJdWgBQDtCE";
      uri_weapons[3] = "QmRXcWincmyskN3CgkcH2FKEnkBvDc5jT9eSYf4EXWcDKc";
      uri_weapons[4] = "QmbFahR5QA8Cn7m9BWxUpNhPqPA5wtUnuvRY8xuGxY8hZS";
      uri_weapons[5] = "QmYJNsTsfdPPQKrhRzGACTvuYa9CKksydaBuGmW9nXDiGr";
      uri_weapons[6] = "QmTCzFLsB5x52Moj1sSeAhWzWsacriGf4nVZfst9o88969";
      uri_weapons[7] = "QmWFp4vBzpdsewYh62nTTvDm1BenX93oQ7YCFNjHWnN81R";
      uri_weapons[8] = "Qmf8mWKZqx7PwJEtGsA4ftqATkd2NYUgPXmH7gRocYBMD4";
      uri_weapons[9] = "QmfDRLJUxSJaQtCJ3hZb9nBJ1NJjpQxSpEuwZwh5zpwV3G";
    }

    else if (variation == 3) { // staff variation
      uri_weapons[0] = "QmQADyin17ZGYoQMnhNDDZDxBbkxSBFUGR7PUphKbkZija";
      uri_weapons[1] = "QmQpXjDz4GQbu4CCaqChtNMWT3ZhCVFG2XX9QmsFkrqpWm";
      uri_weapons[2] = "QmQ8qDRCmK4JiX3YN4PmnfCDK6fCz8ZqViqphikb95DJTW";
      uri_weapons[3] = "QmZfViin5hjc68xyLQLDg2CVeNZTcbyQ2TWMMQ1q2iZTHc";
      uri_weapons[4] = "QmZ9XHhxKtpYWsZKecC68Nc8zqGZsvWKGpfTmmZGvErzcq";
      uri_weapons[5] = "QmZd5yGScv2gvpeFNk5EyivvSK3nWZPnE1ZqfuimcDLkbf";
      uri_weapons[6] = "QmZUcLHX5FLwddEiS4m6b25ytbr7uL8vdcTWFD9AaGQsTY";
      uri_weapons[7] = "QmVv4ZAnUBxsfBkqmNXd6KknH4J3RxBRyVje3MDtDnLm9Z";
      uri_weapons[8] = "QmPA5WhXokmadGZbnNZ7nM7P6p5f2caWk2ptNZKobcaxcD";
      uri_weapons[9] = "QmTLhhXN3zq3h7HQt6J4MjmezKYsjiTWfgH4TL2DuQy1xc";
    }

    else if (variation == 4) { // mace variation
      uri_weapons[0] = "QmSqt58qMkLCHTQhQKAacVJQuiH15E5wtXQp9qU2cSqbKN";
      uri_weapons[1] = "QmRSaiiFmxjAWPEV44qsRxWTCoLz9nw9JEvS7pGcXZ7Md5";
      uri_weapons[2] = "QmNnWY8vzwDsBbZNDtzXggxdCSX6UUemFxwfpJUtUstH87";
      uri_weapons[3] = "Qmcu3W9NbQTefhJWAGmJmvGxtwCqpEhXeG18A5DRHHSjUM";
      uri_weapons[4] = "QmchamVv9zkocT98Cpv4ei9mBL5QiEU78qsMrzQvQFokNN";
      uri_weapons[5] = "Qme4oKNwonPqngEGC7SXnoCnikmuhqEFHakpstAkfG5S15";
      uri_weapons[6] = "QmSr84x3iJK3hjXJxXS4bDBnKdtgHLGKA83KYmqDXEUUod";
      uri_weapons[7] = "QmdueGiKg6Y7LPPa8mofrin9reE46jMeLfXTMqFGWBs4eq";
      uri_weapons[8] = "QmUuoiQzjY5dxh7GwVsirVQj7exbsgtwph9pzZRzDSvT47";
      uri_weapons[9] = "QmTSQoq5QcVw3kZNqUz7fo9DKAaCuQ7y82CWeWQ1RsfxqN";
    }

    return uri_weapons[weapons[tokenId].rarity];
  }
}