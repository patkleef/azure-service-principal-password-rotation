resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-demo-ad-audit"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  retention_in_days   = 30
}

resource "azurerm_monitor_aad_diagnostic_setting" "aad_diagnostics_setting_audit_logs" {
 name               = "audit-logs-to-log-analytics"
 log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
 log {
   category = "AuditLogs"
   enabled  = true
   retention_policy {}
 }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "monitor_scheduled_query_rules_alert" {
  name                = "sqra-pim-group-expiration-${random_integer.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  action {
    action_group = [azurerm_monitor_action_group.monitor_action_group.id]
  }
  data_source_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
  description    = "Query audit log for PIM group assignment expiration"
  enabled        = true
  query          = <<-QUERY
  AuditLogs
    | mv-expand TargetResources
    | where Category == 'GroupManagement'
    | where LoggedByService == 'PIM'
    | where OperationName == 'Remove member from role (PIM activation expired)'
    | sort by TimeGenerated desc
QUERY
  severity       = 3
  frequency      = 5
  time_window    = 5
  trigger {
    operator  = "GreaterThanOrEqual"
    threshold = 1
  }
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace,
    azurerm_monitor_action_group.monitor_action_group
  ]
}

resource "azurerm_monitor_action_group" "monitor_action_group" {
  name                = "ag-pim-group-expiration-${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "pimgexp"

  automation_runbook_receiver {
    name                    = "action_run_book_receiver"
    automation_account_id   = azurerm_automation_account.automation_account.id
    runbook_name            = azurerm_automation_runbook.run_book_change_spn_password.name
    webhook_resource_id     = azurerm_automation_webhook.web_book_change_spn_password.id
    is_global_runbook       = true
    service_uri             = azurerm_automation_webhook.web_book_change_spn_password.uri
    use_common_alert_schema = true
  }
}