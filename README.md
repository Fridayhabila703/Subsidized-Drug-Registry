# 💊 Subsidized Drug Registry

A Clarity smart contract for registering and validating subsidized drugs on the Stacks blockchain, enabling transparent public validation and subsidy distribution.

## 🎯 Overview

The Subsidized Drug Registry provides a decentralized platform for:
- 📋 Registering subsidized drugs with pricing information
- ✅ Validator-based drug approval system
- 📦 Batch tracking for drug distribution
- 👥 Beneficiary registration and subsidy claims
- 🔒 On-chain validation and transparency

## 🚀 Features

### 💊 Drug Registration
- Register drugs with subsidy percentage and pricing
- Automatic subsidized price calculation
- Expiry block height tracking
- Status management (pending/approved/rejected)

### 👨‍⚕️ Validator System
- Validator registration with license verification
- Drug approval/rejection capabilities
- Validation count tracking
- Admin controls for validator management

### 📦 Batch Management
- Add drug batches with manufacturing details
- Track available vs distributed quantities
- Expiry date management
- Distributor assignment

### 👤 Beneficiary System
- Register eligible beneficiaries
- ID-based verification
- Claim subsidy functionality
- Total claimed amount tracking

## 📖 Usage

### Register a Drug
```clarity
(contract-call? .subsidized-drug-registry register-drug 
  "Paracetamol 500mg"
  "PharmaCorp"
  "Painkiller"
  u30  ;; 30% subsidy
  u1000000  ;; 10 STX original price
  u1000)  ;; expires in 1000 blocks
```

### Register as Validator
```clarity
(contract-call? .subsidized-drug-registry register-validator
  "Dr. John Smith"
  "LIC123456")
```

### Validate a Drug
```clarity
(contract-call? .subsidized-drug-registry validate-drug
  u1  ;; drug-id
  true)  ;; approved
```

### Add Drug Batch
```clarity
(contract-call? .subsidized-drug-registry add-drug-batch
  u1  ;; drug-id
  "BATCH001"
  u1000  ;; quantity
  u20241201  ;; manufacturing date
  u20251201)  ;; expiry date
```

### Register as Beneficiary
```clarity
(contract-call? .subsidized-drug-registry register-beneficiary
  "Alice Johnson"
  "ID789012")
```

### Claim Subsidy
```clarity
(contract-call? .subsidized-drug-registry claim-subsidy
  u1  ;; drug-id
  "BATCH001"
  u5)  ;; quantity
```

### Approve Claim
```clarity
(contract-call? .subsidized-drug-registry approve-claim
  u1)  ;; claim-id
```

## 🔍 Read-Only Functions

### Get Drug Information
```clarity
(contract-call? .subsidized-drug-registry get-drug u1)
```

### Get Available Quantity
```clarity
(contract-call? .subsidized-drug-registry get-available-quantity u1 "BATCH001")
```

### Check Drug Validity
```clarity
(contract-call? .subsidized-drug-registry is-drug-valid u1)
```

## 📊 Data Structures

### Drug Record
- `name`: Drug name (string-ascii 100)
- `manufacturer`: Manufacturer name (string-ascii 100)
- `category`: Drug category (string-ascii 50)
- `subsidy-percentage`: Subsidy rate (uint)
- `original-price`: Original price in microSTX (uint)
- `subsidized-price`: Calculated subsidized price (uint)
- `expiry-block`: Block height when registration expires (uint)
- `registrant`: Principal who registered the drug
- `validator`: Optional validator principal
- `status`: Current status (pending/approved/rejected)
- `registration-block`: Block height when registered (uint)

### Validator Record
- `name`: Validator name (string-ascii 100)
- `license-number`: Professional license number (string-ascii 50)
- `active`: Validator status (bool)
- `validation-count`: Number of drugs validated (uint)
- `registration-block`: Registration block height (uint)

## ⚙️ Configuration

- **Registry Fee**: 1 STX (configurable by contract owner)
- **Validation Period**: 144 blocks (configurable)
- **Contract Owner**: Deployer address

## 🔐 Access Control

- **Contract Owner**: Can set fees and deactivate validators
- **Validators**: Can approve/reject drugs (must be registered and active)
- **Drug Registrants**: Can add batches and approve claims for their drugs
- **Beneficiaries**: Can claim subsidies (must be registered and eligible)

## ⚠️ Error Codes

- `u100`: Unauthorized access
- `u101`: Resource already exists
- `u102`: Resource not found
- `u103`: Invalid parameters
- `u104`: Resource expired
- `u105`: Insufficient balance

## 🛠️ Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js for testing

### Testing
```bash
npm install
npm test
```

### Check Contract
```bash
clarinet check
```

## 📝 License

This project is open source and available under the MIT License.

---

Built with ❤️ on Stacks blockchain for transparent healthcare subsidies
