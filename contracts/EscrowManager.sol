// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title EscrowManager
 * @dev Contrato de escrow para gerenciar jobs com milestones entre payer e worker.
 * Suporta ETH e tokens ERC-20, com sistema de disputas e arbitragem.
 */
contract EscrowManager is Ownable, ReentrancyGuard, Pausable {
    // Enums
    enum JobState { Created, Funded, InProgress, Disputed, Completed, Cancelled }

    // Structs
    struct Milestone {
        uint256 amount;
        bool delivered;
        bool approved;
        string cid; // IPFS CID para evidências
    }

    struct Job {
        address payer;
        address worker;
        address arbiter;
        address token; // address(0) para ETH
        uint256 totalAmount;
        JobState state;
        Milestone[] milestones;
        uint256 escrowBalance;
        uint256 disputeFee;
        uint256 createdAt;
    }

    // State variables
    mapping(uint256 => Job) public jobs;
    mapping(address => mapping(address => uint256)) public pendingWithdrawals; // user => token => amount
    uint256 public jobCounter;

    // Events
    event JobCreated(uint256 indexed jobId, address indexed payer, address indexed worker, address arbiter, address token, uint256 totalAmount);
    event JobFunded(uint256 indexed jobId, uint256 amount);
    event JobStarted(uint256 indexed jobId);
    event MilestoneDelivered(uint256 indexed jobId, uint256 indexed milestoneIndex, string cid);
    event MilestoneApproved(uint256 indexed jobId, uint256 indexed milestoneIndex, uint256 amount);
    event DisputeOpened(uint256 indexed jobId, address indexed opener);
    event DisputeResolved(uint256 indexed jobId, uint256 workerAmount, uint256 payerRefund);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event JobCancelled(uint256 indexed jobId);

    // Modifiers
    modifier onlyPayer(uint256 jobId) {
        require(jobs[jobId].payer == msg.sender, "Only payer can call this function");
        _;
    }

    modifier onlyWorker(uint256 jobId) {
        require(jobs[jobId].worker == msg.sender, "Only worker can call this function");
        _;
    }

    modifier onlyArbiter(uint256 jobId) {
        require(jobs[jobId].arbiter == msg.sender, "Only arbiter can call this function");
        _;
    }

    modifier jobExists(uint256 jobId) {
        require(jobId < jobCounter, "Job does not exist");
        _;
    }

    modifier validJobState(uint256 jobId, JobState requiredState) {
        require(jobs[jobId].state == requiredState, "Invalid job state");
        _;
    }

    /**
     * @dev Cria um novo job com milestones.
     * @param worker Endereço do trabalhador
     * @param arbiter Endereço do árbitro
     * @param token Endereço do token (address(0) para ETH)
     * @param amounts Array com os valores de cada milestone
     * @param disputeFee Taxa para abrir disputa
     * @return jobId O ID do job criado
     */
    function createJob(
        address worker,
        address arbiter,
        address token,
        uint256[] calldata amounts,
        uint256 disputeFee
    ) external whenNotPaused returns (uint256 jobId) {
        require(worker != address(0), "Invalid worker address");
        require(arbiter != address(0), "Invalid arbiter address");
        require(amounts.length > 0, "Must have at least one milestone");
        require(amounts.length <= 10, "Maximum 10 milestones per job");
        require(disputeFee > 0, "Dispute fee must be greater than 0");
        require(disputeFee <= 1 ether, "Dispute fee too high");

        // Validar token ERC20 se não for ETH
        if (token != address(0)) {
            require(IERC20(token).totalSupply() > 0, "Invalid ERC20 token");
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Milestone amount must be greater than 0");
            require(amounts[i] <= 100 ether, "Milestone amount too high");
            totalAmount += amounts[i];
        }
        require(totalAmount <= 1000 ether, "Total job amount too high");

        jobId = jobCounter;
        jobCounter++;

        Job storage job = jobs[jobId];
        job.payer = msg.sender;
        job.worker = worker;
        job.arbiter = arbiter;
        job.token = token;
        job.totalAmount = totalAmount;
        job.state = JobState.Created;
        job.disputeFee = disputeFee;
        job.createdAt = block.timestamp;

        for (uint256 i = 0; i < amounts.length; i++) {
            job.milestones.push(Milestone({
                amount: amounts[i],
                delivered: false,
                approved: false,
                cid: ""
            }));
        }

        emit JobCreated(jobId, msg.sender, worker, arbiter, token, totalAmount);
    }

    /**
     * @dev Inicia o job após funding.
     * @param jobId ID do job
     */
    function startJob(uint256 jobId)
        external
        whenNotPaused
        jobExists(jobId)
        onlyPayer(jobId)
        validJobState(jobId, JobState.Funded)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        job.state = JobState.InProgress;

        emit JobStarted(jobId);
    }

    /**
     * @dev Entrega um milestone.
     * @param jobId ID do job
     * @param milestoneIndex Índice do milestone
     * @param cid CID do IPFS com evidências
     */
    function deliverMilestone(uint256 jobId, uint256 milestoneIndex, string calldata cid)
        external
        whenNotPaused
        jobExists(jobId)
        onlyWorker(jobId)
        validJobState(jobId, JobState.InProgress)
    {
        Job storage job = jobs[jobId];
        require(milestoneIndex < job.milestones.length, "Invalid milestone index");
        require(!job.milestones[milestoneIndex].delivered, "Milestone already delivered");

        job.milestones[milestoneIndex].delivered = true;
        job.milestones[milestoneIndex].cid = cid;

        emit MilestoneDelivered(jobId, milestoneIndex, cid);
    }

    /**
     * @dev Aprova um milestone entregue.
     * @param jobId ID do job
     * @param milestoneIndex Índice do milestone
     */
    function approveMilestone(uint256 jobId, uint256 milestoneIndex)
        external
        whenNotPaused
        jobExists(jobId)
        onlyPayer(jobId)
        validJobState(jobId, JobState.InProgress)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        require(milestoneIndex < job.milestones.length, "Invalid milestone index");
        require(job.milestones[milestoneIndex].delivered, "Milestone not delivered yet");
        require(!job.milestones[milestoneIndex].approved, "Milestone already approved");
        require(job.escrowBalance >= job.milestones[milestoneIndex].amount, "Insufficient escrow balance");

        // Effects
        job.milestones[milestoneIndex].approved = true;
        job.escrowBalance -= job.milestones[milestoneIndex].amount;
        pendingWithdrawals[job.worker][job.token] += job.milestones[milestoneIndex].amount;

        // Check if all milestones are approved
        bool allApproved = true;
        for (uint256 i = 0; i < job.milestones.length; i++) {
            if (!job.milestones[i].approved) {
                allApproved = false;
                break;
            }
        }

        if (allApproved) {
            job.state = JobState.Completed;
        }

        emit MilestoneApproved(jobId, milestoneIndex, job.milestones[milestoneIndex].amount);
    }

    /**
     * @dev Abre uma disputa para o job.
     * @param jobId ID do job
     */
    function openDispute(uint256 jobId)
        external
        payable
        whenNotPaused
        jobExists(jobId)
        validJobState(jobId, JobState.InProgress)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        require(msg.sender == job.payer || msg.sender == job.worker, "Only payer or worker can open dispute");
        require(msg.value >= job.disputeFee, "Insufficient dispute fee");

        // Effects
        job.state = JobState.Disputed;

        // Refund excess fee
        if (msg.value > job.disputeFee) {
            payable(msg.sender).transfer(msg.value - job.disputeFee);
        }

        emit DisputeOpened(jobId, msg.sender);
    }

    /**
     * @dev Resolve uma disputa.
     * @param jobId ID do job
     * @param workerAmount Quantia para o worker
     * @param payerRefund Quantia para reembolso do payer
     */
    function resolveDispute(uint256 jobId, uint256 workerAmount, uint256 payerRefund)
        external
        whenNotPaused
        jobExists(jobId)
        onlyArbiter(jobId)
        validJobState(jobId, JobState.Disputed)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        require(workerAmount + payerRefund <= job.escrowBalance, "Invalid distribution amounts");
        require(workerAmount >= 0 && payerRefund >= 0, "Amounts cannot be negative");

        uint256 totalDistributed = workerAmount + payerRefund;
        uint256 remaining = job.escrowBalance - totalDistributed;

        // Effects
        job.state = JobState.Completed;
        job.escrowBalance = remaining; // Remaining goes to arbiter as fee

        if (workerAmount > 0) {
            pendingWithdrawals[job.worker][job.token] += workerAmount;
        }

        if (payerRefund > 0) {
            pendingWithdrawals[job.payer][job.token] += payerRefund;
        }

        if (remaining > 0) {
            pendingWithdrawals[job.arbiter][job.token] += remaining;
        }

        emit DisputeResolved(jobId, workerAmount, payerRefund);
    }

    /**
     * @dev Retira fundos pendentes.
     * @param token Endereço do token
     */
    function withdraw(address token) external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender][token];
        require(amount > 0, "No funds to withdraw");

        // Effects
        pendingWithdrawals[msg.sender][token] = 0;

        // Interactions
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, token, amount);
    }

    /**
     * @dev Cancela um job não iniciado.
     * @param jobId ID do job
     */
    function cancelJob(uint256 jobId)
        external
        whenNotPaused
        jobExists(jobId)
        onlyPayer(jobId)
        validJobState(jobId, JobState.Created)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        job.state = JobState.Cancelled;

        // Refund escrow
        if (job.escrowBalance > 0) {
            pendingWithdrawals[job.payer][job.token] += job.escrowBalance;
            job.escrowBalance = 0;
        }

        emit JobCancelled(jobId);
    }

    /**
     * @dev Pausa o contrato (only owner).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Despausa o contrato (only owner).
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Recebe funding para um job.
     * @param jobId ID do job
     */
    function fundJob(uint256 jobId)
        external
        payable
        whenNotPaused
        jobExists(jobId)
        validJobState(jobId, JobState.Created)
        nonReentrant
    {
        Job storage job = jobs[jobId];
        require(msg.sender == job.payer, "Only payer can fund");

        uint256 amount = msg.value;
        if (job.token != address(0)) {
            require(msg.value == 0, "Cannot send ETH for ERC20 job");
            IERC20(job.token).transferFrom(msg.sender, address(this), job.totalAmount);
            amount = job.totalAmount;
        } else {
            require(msg.value == job.totalAmount, "Incorrect funding amount");
        }

        // Effects
        job.escrowBalance = amount;
        job.state = JobState.Funded;

        emit JobFunded(jobId, amount);
    }

    /**
     * @dev Retorna os detalhes de um job.
     * @param jobId ID do job
     */
    function getJob(uint256 jobId) external view jobExists(jobId) returns (
        address payer,
        address worker,
        address arbiter,
        address token,
        uint256 totalAmount,
        JobState state,
        uint256 escrowBalance,
        uint256 milestonesCount
    ) {
        Job storage job = jobs[jobId];
        return (
            job.payer,
            job.worker,
            job.arbiter,
            job.token,
            job.totalAmount,
            job.state,
            job.escrowBalance,
            job.milestones.length
        );
    }

    /**
     * @dev Retorna os detalhes de um milestone.
     * @param jobId ID do job
     * @param milestoneIndex Índice do milestone
     */
    function getMilestone(uint256 jobId, uint256 milestoneIndex)
        external
        view
        jobExists(jobId)
        returns (uint256 amount, bool delivered, bool approved, string memory cid)
    {
        require(milestoneIndex < jobs[jobId].milestones.length, "Invalid milestone index");
        Milestone storage milestone = jobs[jobId].milestones[milestoneIndex];
        return (milestone.amount, milestone.delivered, milestone.approved, milestone.cid);
    }

    /**
     * @dev Retorna o saldo pendente de retirada para um usuário e token.
     * @param user Endereço do usuário
     * @param token Endereço do token
     */
    function getPendingWithdrawal(address user, address token) external view returns (uint256) {
        return pendingWithdrawals[user][token];
    }

    /**
     * @dev Retorna estatísticas gerais do contrato.
     */
    function getContractStats() external view returns (uint256 totalJobs) {
        return jobCounter;
    }
}