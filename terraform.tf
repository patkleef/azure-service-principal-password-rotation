terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.19"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {
}