# DineChain

DineChain is a decentralized application built on the Stacks blockchain that revolutionizes how friends split restaurant bills. By leveraging smart contracts and blockchain technology, DineChain eliminates the awkwardness and potential conflicts that often arise when dining out in groups.

## Project Overview

Going out to eat with friends should be about enjoying the experience, not stressing over bill payment. DineChain solves this common social friction point by allowing diners to commit funds beforehand and automating the bill-splitting process through secure smart contracts on the Stacks blockchain.

When a group decides to dine together, they can create a dining session through DineChain. Each participant commits their share of the expected bill to a smart contract wallet. Upon completion of the meal, the restaurant can initiate a payment request through a simple QR code system, triggering the automatic disbursement of funds from the smart contract.

## Core Features

DineChain introduces several innovative features to make group dining payments seamless:

### Smart Contract Wallet
Each dining session creates a temporary group wallet that holds participant contributions. The smart contract ensures that funds can only be released to the verified restaurant address, providing security and peace of mind for all parties involved.

### QR Code Integration
Restaurants can generate unique QR codes for each table or bill, which diners can scan to join the payment session. This creates a frictionless experience while maintaining the security of blockchain transactions.

### Participant Management
The system tracks all participants in a dining session, managing their contributions and ensuring fair distribution of the final bill. Each participant's commitment is recorded on the blockchain, providing transparency and accountability.

### Restaurant Verification
To maintain system integrity, restaurants go through a verification process before being able to receive payments through DineChain. This ensures that only legitimate establishments can participate in the ecosystem.

## Technical Architecture

DineChain is built using the following technologies:

- Stacks Blockchain: Provides the underlying blockchain infrastructure with Bitcoin-level security
- Clarity Smart Contracts: Powers the secure and transparent handling of funds
- Web3 Frontend: Offers an intuitive interface for both diners and restaurants
- Stacks API: Enables seamless interaction between the frontend and blockchain

The smart contract architecture includes:
- Session management for dining groups
- Participant fund handling
- Restaurant payment processing
- Security measures and verification systems

## Getting Started

### Prerequisites
- Stacks Wallet
- Node.js (version 14 or higher)
- Git

### Installation
1. Clone the repository:
```bash
git clone https://github.com/gboigwe/dinechain.git
cd dinechain
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your specific configuration
```

4. Start the development server:
```bash
npm run dev
```

## Contributing

We welcome contributions to DineChain! Whether you're interested in fixing bugs, adding new features, or improving documentation, please feel free to make a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Security

DineChain takes security seriously. All smart contracts have been designed with security best practices in mind. However, as this is a financial application, we recommend:

- Starting with small transactions during testing
- Reviewing smart contract code before use
- Being aware of transaction fees and gas costs
- Verifying restaurant addresses before committing funds

## Future Roadmap

We have several exciting features planned for future releases:

- Integration with traditional payment systems
- Advanced bill splitting based on individual orders
- Loyalty program integration
- Mobile application development
- Multi-currency support

## Contact

Project Link: [https://github.com/gboigwe/dinechain](https://github.com/gboigwe/DineChain)

For support or inquiries, please open an issue in the GitHub repository.
