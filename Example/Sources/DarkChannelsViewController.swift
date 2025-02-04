//
//  DarkChannelsViewController.swift
//  ChatExample
//
//  Created by Alexey Bukhtin on 27/08/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit
import RxSwift
import RxGesture
import StreamChatCore
import StreamChat

final class DarkChannelsViewController: ChannelsViewController {
    
    override var defaultStyle: ChatViewStyle {
        return .dark
    }
    
    @IBOutlet weak var logoutButton: UIBarButtonItem!
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setup() {
        deleteChannelBySwipe = true
        title = "My channels"
        setupPresenter()
        observeInvites()
    }
    
    func setupPresenter() {
        if let currentUser = User.current {
            channelsPresenter = ChannelsPresenter(filter: .key("members", .in([currentUser.id])))
        }
    }
    
    func observeInvites() {
        Client.shared.onEvent([.notificationInvited,
                               .notificationInviteAccepted,
                               .notificationInviteRejected,
                               .memberUpdated])
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] event in self?.handleInviteEvent(event) })
            .disposed(by: disposeBag)
    }
    
    func handleInviteEvent(_ event: StreamChatCore.Event) {
        if case .notificationInvited(let channel, _) = event {
            let alert = UIAlertController(title: "Invite",
                                          message: "You are invited to the \(channel.name) channel",
                preferredStyle: .alert)
            
            alert.addAction(.init(title: "Accept", style: .default, handler: { [unowned self] _ in
                channel.acceptInvite().subscribe().disposed(by: self.disposeBag)
            }))
            
            alert.addAction(.init(title: "Reject", style: .destructive, handler: { [unowned self] _ in
                channel.rejectInvite().subscribe().disposed(by: self.disposeBag)
            }))
            
            present(alert, animated: true)
            return
        }
        
        if case .notificationInviteAccepted = event {
            Banners.shared.show("🙋🏻‍♀️ Invite accepted")
            channelsPresenter.reload()
        }
        
        if case .notificationInviteRejected = event {
            Banners.shared.show("🙅🏻‍♀️ Invite rejected")
        }
        
        if case .memberUpdated(let member, _) = event {
            if member.inviteAccepted != nil {
                Banners.shared.show("🙋🏻‍♀️ \(member.user.name) accepted invite")
            } else if member.inviteRejected != nil {
                Banners.shared.show("🙅🏻‍♀️ \(member.user.name) rejected invite")
            }
        }
    }
    
    @IBAction func addChannel(_ sender: Any) {
        let number = Int.random(in: 1000...9999)
        let channel = Channel(type: .messaging, id: "new_channel_\(number)", name: "Channel \(number)")
        channel.create().subscribe().disposed(by: disposeBag)
    }
    
    override func channelCell(at indexPath: IndexPath, channelPresenter: ChannelPresenter) -> UITableViewCell {
        let cell = super.channelCell(at: indexPath, channelPresenter: channelPresenter)
        
        if let cell = cell as? ChannelTableViewCell {
            var extraChannelName = "🙋🏻‍♀️\(channelPresenter.channel.members.count)"
            
            // Add an unread count.
            if channelPresenter.channel.currentUnreadCount > 0 {
                extraChannelName += " 📬\(channelPresenter.channel.currentUnreadCount)"
            }
            
            // Add a number of members.
            cell.nameLabel.text = "\(cell.nameLabel.text ?? "") \(extraChannelName)"
            
            cell.rx.longPressGesture().when(.began)
                .subscribe(onNext: { [weak self, weak channelPresenter] _ in
                    if let self = self, let channelPresenter = channelPresenter {
                        self.showMenu(for: channelPresenter)
                    }
                })
                .disposed(by: cell.disposeBag)
        }
        
        return cell
    }
    
    override func createChatViewController(with channelPresenter: ChannelPresenter, indexPath: IndexPath) -> ChatViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: .main)
        
        guard let chatViewController = storyboard.instantiateViewController(withIdentifier: "CustomChatViewController") as? CustomChatViewController else {
            print("❌ Can't find CustomChatViewController in Main.storyboard")
            return super.createChatViewController(with: channelPresenter, indexPath: indexPath)
        }
        
        chatViewController.style = style
        channelPresenter.eventsFilter = channelsPresenter.channelEventsFilter
        chatViewController.channelPresenter = channelPresenter
        return chatViewController
    }
    
    override func show(chatViewController: ChatViewController) {
        if let channel = chatViewController.channelPresenter?.channel {
            channel.banEnabling = .enabled(timeoutInMinutes: 1, reason: "I don't like you 🤮")
            
            channel.onEvent(.userBanned)
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { event in
                    if case .userBanned(_, let reason, _, _, _) = event {
                        Banners.shared.show("🙅‍♂️ You are banned: \(reason ?? "No reason")")
                    }
                })
                .disposed(by: chatViewController.disposeBag)
        }
        
        super.show(chatViewController: chatViewController)
    }
    
    @IBAction func logout(_ sender: Any) {
        if logoutButton.title == "Logout" {
            Client.shared.disconnect()
            logoutButton.title = "Login"
        } else if let delegate = UIApplication.shared.delegate as? AppDelegate,
            let navigationController = delegate.window?.rootViewController as? UINavigationController,
            let loginViewController = navigationController.viewControllers.first as? LoginViewController {
            loginViewController.login(animated: true)
            setupPresenter()
            logoutButton.title = "Logout"
        }
    }
    
    func showMenu(for channelPresenter: ChannelPresenter) {
        let alertController = UIAlertController(title: channelPresenter.channel.name, message: nil, preferredStyle: .actionSheet)
        alertController.addAction(.init(title: "Cancel", style: .cancel, handler: { _ in }))
        
        if (channelPresenter.channel.createdBy?.isCurrent ?? false) {
            alertController.addAction(.init(title: "Rename", style: .default, handler: { [weak self] _ in
                if let self = self {
                    channelPresenter.channel
                        .update(name: "Updated \(Int.random(in: 100...999))", imageURL: URL(string: "https://bit.ly/321RmWb")!)
                        .subscribe()
                        .disposed(by: self.disposeBag)
                }
            }))
        }
        
        present(alertController, animated: true)
    }
    
    @IBAction func showGeneral(_ sender: UIBarButtonItem) {
        let channel = Channel(type: .messaging, id: "general")
        sender.isEnabled = false
        
        channel.show()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                sender.isEnabled = true
                self?.channelsPresenter.reload()
            })
            .disposed(by: disposeBag)
    }
}
