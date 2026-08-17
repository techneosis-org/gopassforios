//
//  StoreEditViewController.swift
//  pass
//

import passKit
import SVProgressHUD
import UIKit

/// Form for adding or editing one mounted store.
///
/// Built in code for the same reason as the list: the storyboard's settings
/// screens are static, and this one is reused for both adding and editing.
final class StoreEditViewController: UITableViewController, PasswordAlertPresenter {
    private let manager = PasswordStoreManager.shared
    private let registry = PasswordStoreRegistry.shared

    /// The store being edited, or nil when adding one.
    private let existing: PasswordStoreConfig?

    private let nameField = UITextField()
    private let urlField = UITextField()
    private let branchField = UITextField()
    private let usernameField = UITextField()
    private let authControl = UISegmentedControl(items: ["Password".localize(), "SSHKey".localize()])

    init(config: PasswordStoreConfig? = nil) {
        self.existing = config
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used; this screen is created in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existing == nil ? "AddStore".localize() : existing?.name
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )

        nameField.placeholder = "StoreNamePlaceholder".localize()
        nameField.autocapitalizationType = .none
        nameField.autocorrectionType = .no
        urlField.placeholder = "ssh://git@example.com/store.git"
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL
        branchField.text = "main"
        branchField.autocapitalizationType = .none
        usernameField.text = "git"
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        authControl.selectedSegmentIndex = 0

        if let existing {
            nameField.text = existing.name
            urlField.text = existing.gitURL.absoluteString
            branchField.text = existing.branchName
            usernameField.text = existing.username
            authControl.selectedSegmentIndex = existing.authenticationMethod == .password ? 0 : 1
        }
    }

    // MARK: - Form

    private enum Row: Int, CaseIterable {
        case name, url, branch, username, auth

        var label: String {
            switch self {
            case .name:
                return "Name".localize()
            case .url:
                return "URL".localize()
            case .branch:
                return "Branch".localize()
            case .username:
                return "Username".localize()
            case .auth:
                return "Authentication".localize()
            }
        }
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "field", for: indexPath)
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        guard let row = Row(rawValue: indexPath.row) else {
            return cell
        }

        let label = UILabel()
        label.text = row.label
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .horizontal)

        let control: UIView = {
            switch row {
            case .name:
                return nameField
            case .url:
                return urlField
            case .branch:
                return branchField
            case .username:
                return usernameField
            case .auth:
                return authControl
            }
        }()

        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        return cell
    }

    // MARK: - Saving

    @objc
    private func save() {
        guard let name = nameField.text?.trimmed, !name.isEmpty else {
            Utils.alert(title: "CannotAddStore".localize(), message: "StoreNameRequired.".localize(), controller: self)
            return
        }
        guard name != Defaults.legacyStoreName else {
            Utils.alert(title: "CannotAddStore".localize(), message: AppError.storeNameDuplicated.localizedDescription, controller: self)
            return
        }
        guard let urlText = urlField.text?.trimmed, let url = URL(string: urlText), !urlText.isEmpty else {
            Utils.alert(title: "CannotAddStore".localize(), message: "StoreURLRequired.".localize(), controller: self)
            return
        }

        let config = PasswordStoreConfig(
            name: name,
            gitURL: url,
            id: existing?.id ?? UUID(),
            branchName: branchField.text?.trimmed.isEmpty == false ? branchField.text!.trimmed : "main",
            authenticationMethod: authControl.selectedSegmentIndex == 0 ? .password : .key,
            username: usernameField.text?.trimmed.isEmpty == false ? usernameField.text!.trimmed : "git"
        )

        do {
            if existing == nil {
                try manager.add(config)
            } else {
                try registry.update(config)
                // The remote or branch may have changed, so the checkout is
                // re-cloned rather than left pointing at the old history.
                manager.forget(configID: config.id)
            }
        } catch {
            Utils.alert(title: "CannotAddStore".localize(), message: error.localizedDescription, controller: self)
            return
        }

        cloneAndPop(config)
    }

    private func cloneAndPop(_ config: PasswordStoreConfig) {
        Defaults.isRememberGitCredentialPassphraseOn = true
        SVProgressHUD.setDefaultMaskType(.black)
        SVProgressHUD.show(withStatus: "Cloning Remote Repository")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.manager.clone(
                    config,
                    passwordProvider: self.present,
                    transferProgressBlock: { progress, _ in
                        let received = progress.pointee
                        guard received.total_objects > 0 else {
                            return
                        }
                        SVProgressHUD.showProgress(Float(received.received_objects) / Float(received.total_objects), status: "Cloning Remote Repository")
                    },
                    checkoutProgressBlock: { _, completed, total in
                        guard total > 0 else {
                            return
                        }
                        SVProgressHUD.showProgress(Float(completed) / Float(total), status: "CheckingOutBranch".localize(config.branchName))
                    }
                )
                DispatchQueue.main.async {
                    SVProgressHUD.dismiss()
                    NotificationCenter.default.post(name: .passwordStoreUpdated, object: nil)
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                // The mount is dropped again: a configured store that failed to
                // clone would sit in the list looking usable.
                self.registry.remove(withID: config.id)
                DispatchQueue.main.async {
                    SVProgressHUD.dismiss()
                    Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self)
                }
            }
        }
    }
}
