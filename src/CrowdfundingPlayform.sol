// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CampaignToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

contract CrowdfundingPlatform {
    struct Campaign {
        address owner;
        uint256 goalAmount;
        uint256 deadline;
        uint256 amountRaised;
        bool completed;
        address rewardToken;
        mapping(address => uint256) contributions;
    }

    uint256 public campaignCounter;
    mapping(uint256 => Campaign) public campaigns;

    event CampaignCreated(
        uint256 indexed campaignId, address indexed owner, uint256 goalAmount, uint256 deadline, address rewardToken
    );
    event ContributionMade(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event RefundIssued(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event GoalReached(uint256 indexed campaignId, uint256 amountRaised);

    modifier onlyCampaignOwner(uint256 campaignId) {
        require(campaigns[campaignId].owner == msg.sender, "Not the campaign owner");
        _;
    }

    function createCampaign(
        uint256 goalAmount,
        uint256 durationInDays,
        string memory tokenName,
        string memory tokenSymbol
    ) external {
        require(goalAmount > 0, "Goal amount must be greater than zero");

        CampaignToken rewardToken = new CampaignToken(tokenName, tokenSymbol);
        campaignCounter++;

        Campaign storage newCampaign = campaigns[campaignCounter];
        newCampaign.owner = msg.sender;
        newCampaign.goalAmount = goalAmount;
        newCampaign.deadline = block.timestamp + (durationInDays * 1 days);
        newCampaign.rewardToken = address(rewardToken);

        emit CampaignCreated(campaignCounter, msg.sender, goalAmount, newCampaign.deadline, address(rewardToken));
    }

    function contribute(uint256 campaignId) external payable {
        Campaign storage campaign = campaigns[campaignId];

        require(block.timestamp <= campaign.deadline, "Campaign has ended");
        require(msg.value > 0, "Contribution must be greater than zero");
        require(!campaign.completed, "Campaign already completed");

        campaign.amountRaised += msg.value;
        campaign.contributions[msg.sender] += msg.value;

        // Mint reward tokens proportional to contribution
        uint256 rewardAmount = msg.value / 1 ether * 100; // Example: 1 ETH = 100 tokens
        CampaignToken(campaign.rewardToken).mint(msg.sender, rewardAmount);

        emit ContributionMade(campaignId, msg.sender, msg.value);

        // Check if goal is reached
        if (campaign.amountRaised >= campaign.goalAmount) {
            campaign.completed = true;
            emit GoalReached(campaignId, campaign.amountRaised);
        }
    }

    function claimFunds(uint256 campaignId) external onlyCampaignOwner(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        require(campaign.completed, "Campaign goal not reached");
        require(campaign.amountRaised > 0, "No funds to claim");

        uint256 amount = campaign.amountRaised;
        campaign.amountRaised = 0;

        (bool success,) = campaign.owner.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function requestRefund(uint256 campaignId) external {
        Campaign storage campaign = campaigns[campaignId];

        require(block.timestamp > campaign.deadline, "Campaign still active");
        require(!campaign.completed, "Campaign goal was reached");

        uint256 contribution = campaign.contributions[msg.sender];
        require(contribution > 0, "No contributions to refund");

        campaign.contributions[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: contribution}("");
        require(success, "Refund failed");

        emit RefundIssued(campaignId, msg.sender, contribution);
    }
}
