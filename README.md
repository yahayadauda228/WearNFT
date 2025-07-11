# 👕 WearNFT - Decentralized Merch Store

> Link physical products to NFTs and create a seamless bridge between digital ownership and real-world merchandise! 🌉

## 🚀 Overview

WearNFT is a revolutionary smart contract that enables creators to sell physical merchandise as NFTs on the Stacks blockchain. Each NFT represents ownership of a real-world product, complete with size, color, and shipping tracking capabilities.

## ✨ Features

- 🎨 **NFT-Linked Merchandise**: Each NFT represents a physical product
- 🏪 **Built-in Marketplace**: Buy, sell, and trade merchandise NFTs
- 📦 **Shipping Integration**: Track physical product delivery
- 👔 **Product Variants**: Support for different sizes and colors
- 🛒 **Direct Purchase**: Buy NFTs that automatically trigger physical fulfillment
- 📊 **Inventory Management**: Template-based product management

## 🛠️ Core Functions

### For Store Owners
- `add-product-template`: Create new merchandise templates
- `mint-nft`: Mint NFTs for specific products
- `mark-shipped`: Update shipping status with tracking info

### For Customers
- `purchase-nft`: Buy merchandise NFTs directly
- `list-for-sale`: List owned NFTs on marketplace
- `buy-from-marketplace`: Purchase from other users
- `cancel-listing`: Remove marketplace listings

### Read-Only Functions
- `get-token-metadata`: View product details
- `get-marketplace-listing`: Check listing information
- `is-shipped`: Check shipping status
- `get-tracking-info`: Get tracking number

## 🎯 Usage Examples

### Initialize Contract
```clarity
(contract-call? .WearNFT initialize-contract "https://api.wearnft.com/metadata/")
```

### Add Product Template
```clarity
(contract-call? .WearNFT add-product-template 
    "hoodie-basic" 
    u1000000 
    (list "XS" "S" "M" "L" "XL") 
    (list "black" "white" "red") 
    u100)
```

### Purchase NFT
```clarity
(contract-call? .WearNFT purchase-nft "hoodie-basic" "L" "black")
```

### List for Sale
```clarity
(contract-call? .WearNFT list-for-sale u1 u1200000)
```

## 🏗️ Getting Started

1. **Deploy Contract**: Deploy WearNFT.clar to Stacks blockchain
2. **Initialize**: Call `initialize-contract` with your metadata URI
3. **Add Products**: Create product templates with `add-product-template`
4. **Start Selling**: Customers can now purchase NFTs linked to physical products!

## 🔧 Development

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Local Testing
```bash
clarinet console
```

### Deploy
```bash
clarinet deploy
```

## 🎨 Use Cases

- **Band Merchandise**: Musicians selling tour shirts as NFTs
- **Fashion Brands**: Limited edition clothing with digital certificates
- **Event Swag**: Conference merchandise with proof of attendance
- **Collectible Apparel**: Rare designs with blockchain verification
- **Custom Orders**: Personalized products with NFT ownership

## 🔒 Security Features

- Owner-only administrative functions
- Token ownership verification
- Price validation
- Supply limit enforcement
- Secure STX transfers

## 🌟 Why WearNFT?

- **Authenticity**: Blockchain-verified genuine merchandise
- **Resale Value**: Trade physical products as digital assets
- **Transparency**: Public shipping and ownership records
- **Innovation**: Bridge physical and digital commerce
- **Community**: Build engaged customer communities

## 📈 Future Enhancements

- Multi-signature product approval
- Royalty distribution for resales
- Integration with shipping APIs
- Mobile app for easy management
- Cross-chain compatibility


