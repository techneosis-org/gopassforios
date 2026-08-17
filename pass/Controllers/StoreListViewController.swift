//
//  StoreListViewController.swift
//  pass
//

import passKit
import SVProgressHUD
import UIKit

/// Lists the mounted stores and lets new ones be added.
///
/// Built in code rather than the storyboard: the settings screens there are
/// static tables, and this one is driven by however many stores are configured.
final class StoreListViewController: UITableViewController {
    private let registry = PasswordStoreRegistry.shared
    private let manager = PasswordStoreManager.shared

    private var configs: [PasswordStoreConfig] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stores".localize()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addStore)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configs = registry.configs
        tableView.reloadData()
    }

    @objc
    private func addStore() {
        navigationController?.pushViewController(StoreEditViewController(), animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : configs.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "OriginalStore".localize() : "MountedStores".localize()
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "OriginalStoreExplanation.".localize() : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Subtitle cells are built by hand: the deployment target predates
        // UIListContentConfiguration.
        let cell = tableView.dequeueReusableCell(withIdentifier: "store") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "store")
        if indexPath.section == 0 {
            cell.textLabel?.text = Defaults.legacyStoreName
            cell.detailTextLabel?.text = Defaults.gitURL.host
        } else {
            let config = configs[indexPath.row]
            cell.textLabel?.text = config.name
            cell.detailTextLabel?.text = config.gitURL.absoluteString
        }
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = indexPath.section == 0 ? .none : .disclosureIndicator
        return cell
    }

    override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // The original store is not removable here: it is the clone the app was
        // set up with, and erasing it belongs in the existing settings screen.
        indexPath.section == 1
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.section == 1 else {
            return
        }
        let config = configs[indexPath.row]
        let alert = UIAlertController(
            title: "RemoveStore?".localize(),
            message: "RemoveStoreExplanation.".localize(config.name),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Remove".localize(), style: .destructive) { _ in
            self.remove(config)
            tableView.reloadData()
        })
        alert.addAction(UIAlertAction.cancel())
        alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else {
            return
        }
        navigationController?.pushViewController(StoreEditViewController(config: configs[indexPath.row]), animated: true)
    }

    private func remove(_ config: PasswordStoreConfig) {
        manager.remove(config)
        configs = registry.configs
    }
}
