//
//  OldCardView.swift
//  App framework
//
//  Created by Artur Gurgul on 11/09/2020.
//  Copyright © 2020 Winux-ORG. All rights reserved.
//


import UIKit
import SwiftUI
import Combine

private let thereshold = CGFloat(30)
private let closingSpeed = CGFloat(400)

public enum CardType {
    case error(title: String)
    case list
    case any(view: AnyView?, openedHeight: CGFloat)
    case blocking(view: AnyView?)
    case none
    case unknown
}

struct CardView<Content: View>: UIViewControllerRepresentable {

//    @Binding var cardType: CardType
//    var cardState: CardStatePassthroughSubject

    var content: () -> Content
    let cards: Cards

    init(cards: Cards, @ViewBuilder content: @escaping () -> Content) {
//        self._cardType = cardType
//        self.cardState = cardState
        self.content = content
        self.cards = cards
    }

    func makeUIViewController(context: Context) -> CardHolderViewController<Content> {
        let holerViewController = CardHolderViewController(cards: cards, rootView: content())
        holerViewController.view.clipsToBounds = true
        return holerViewController
    }

    var lastState = CardType.none

    func updateUIViewController(_ viewController: CardHolderViewController<Content>, context: Context) {
        viewController.rootView = self.content()

//        switch cardType {
//        case .error(let title):
//            viewController.show(view: errorView(title: title), full: false)
//        case .list:
//            viewController.show(view:list() ,full: true)
//        case .any(let view, let openedHeight):
//            viewController.show(view:view ,full: true, openedHeight: openedHeight)
//        case .blocking(let view):
//            viewController.show(view:view ,full: false)
//        case .none:
//            viewController.close()
//        case .unknown:
//            break
//        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: CardView

        init(_ parent: CardView) {
            self.parent = parent
            super.init()
        }
    }
}

private extension CALayer {
    func adjustCorners(with offset: CGFloat) {
        if offset < 60 {
            let radius = floor(offset/60 * 12.0)
            if cornerRadius != radius {
                cornerRadius = radius
            }
        }
    }
}

extension UIView {

    func roundCorners(corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }

    func addView(view: UIView) {
        addSubview(view)

        let views: [String: UIView] = ["contentView": view]

        view.translatesAutoresizingMaskIntoConstraints = false

        var allConstraints = [NSLayoutConstraint]()
        let vertical = NSLayoutConstraint.constraints(withVisualFormat: "V:|-(0)-[contentView]-(0)-|", options: [], metrics: nil, views: views)
        allConstraints += vertical
        let horizontal = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(0)-[contentView]-(0)-|", options: [], metrics: nil, views: views)
        allConstraints += horizontal
        NSLayoutConstraint.activate(allConstraints)
    }
}

extension UIView {
    func calculatedHeight() -> CGFloat {
        return systemLayoutSizeFitting(CGSize(width: frame.size.width /* 375 */, height: 40)).height
    }
}

class CardHolderViewController<Content>: UIViewController where Content: View {

    private let hostingViewController: UIHostingController<Content>

    private var blockingCardScrollView: CardScrollView?
    private var normalCardScrollView: CardScrollView?
    private var notClosableCardScrollView: CardScrollView?


    var bag = Set<AnyCancellable>()
    let cards: Cards

    init(cards: Cards, rootView: Content) {
        hostingViewController = UIHostingController(rootView: rootView)
        self.rootView = rootView

        self.cards = cards

        super.init(nibName: nil, bundle: nil)

        addChild(hostingViewController)
        view.addView(view: hostingViewController.view)
        hostingViewController.didMove(toParent: self)


        cards.blockingCard.events.showCardViewAction.sink(receiveValue: openBlockingCard).store(in: &bag)
        cards.normalCard.events.showCardViewAction.sink(receiveValue: normalCard).store(in: &bag)
        cards.notClosableCard.events.showCardViewAction.sink(receiveValue: notClosableCard).store(in: &bag)

        cards.blockingCard.events.closeCardAction.sink(receiveValue: blockingCardDidClosed).store(in: &bag)
        cards.normalCard.events.closeCardAction.sink(receiveValue: normalCardDidClosed).store(in: &bag)
        cards.notClosableCard.events.closeCardAction.sink(receiveValue: notClosableCardDidClosed).store(in: &bag)
    }

    func blockingCardDidClosed(closingEvent: ClosingEvent) {
        blockingView?.removeFromSuperview()
        blockingView = nil
        blockingCardScrollView?.close {
            self.cards.blockingCard.events.cardDidClosed.send(closingEvent)
        }
        blockingCardScrollView = nil
    }

    func normalCardDidClosed(closingEvent: ClosingEvent) {
        normalCardScrollView?.close {
            self.cards.normalCard.events.cardDidClosed.send(closingEvent)
        }

        normalCardScrollView = nil
    }

    func notClosableCardDidClosed(closingEvent: ClosingEvent) {
        notClosableCardScrollView?.close {
            self.cards.notClosableCard.events.cardDidClosed.send(closingEvent)
        }
        notClosableCardScrollView = nil
    }

    func openBlockingCard(view: AnyView, isBlocking: Bool, isFullScreen: Bool, openingHeigh: CGFloat) {
        show(scrollView: &blockingCardScrollView, card: cards.blockingCard, view: view, isBlocking: isBlocking, full: isFullScreen, openedHeight: openingHeigh)
    }

    func normalCard(view: AnyView, isBlocking: Bool, isFullScreen: Bool, openingHeigh: CGFloat) {
        show(scrollView: &normalCardScrollView, card: cards.normalCard, view: view, full: isFullScreen, openedHeight: openingHeigh)
    }

    func notClosableCard(view: AnyView, isBlocking: Bool, isFullScreen: Bool, openingHeigh: CGFloat) {
        show(scrollView: &notClosableCardScrollView, card: cards.notClosableCard, view: view, full: isFullScreen, openedHeight: openingHeigh)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var rootView: Content {
        didSet {
            hostingViewController.rootView = rootView
        }
    }

    var blockingView: UIView?

    func show<V>(scrollView: inout CardScrollView?, card: Card, view: V, isBlocking: Bool = false, full: Bool, openedHeight: CGFloat = 100) where V: View {
        scrollView?.removeFromSuperview()
        blockingView?.removeFromSuperview()
        blockingView = nil

        if isBlocking {
            let blockingView = UIView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: self.view.frame.size.height))
            self.view.addSubview(blockingView)

            blockingView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
            self.blockingView = blockingView
        }

        if full {
            scrollView = UIKitFullScreenCardView(card: card, content: view, openedHeight: openedHeight)

        } else {
            scrollView = UIKitCardView(card: card, content: view)
        }

        self.view.addSubview(scrollView!)

        scrollView?.contentSize = CGSize(width: 1000, height: 1000)

        self.view.setNeedsLayout()
        //self.view.layoutIfNeeded()

        scrollView?.open()
    }

    func close() {
        //self.scrollView?.close(completion: nil)
    }
}

protocol CardScrollView: UIScrollView {
    func open()
    func close(completion:(()-> Void)?)
}

class UIKitCardView<Content>: UIScrollView, CardScrollView, UIScrollViewDelegate where Content : View {
    //var dismissed: ()->Void
    func middleHeight() -> CGFloat { content.calculatedHeight() }

//    @Binding var cardType: CardType
//    var cardState: CardStatePassthroughSubject

    let content: UIView

    let card: Card

    init(card: Card, content: Content) {
        self.content = UIHostingController(rootView: content).view
        //self.dismissed = dismissed
//        self._cardType = cardType
//        self.cardState = cardState
        self.card = card

        super.init(frame: .zero)

        self.content.translatesAutoresizingMaskIntoConstraints = false

        addSubview(self.content)
        let views: [String: UIView] = ["contentView": self.content, "superview": self]

        var allConstraints = [NSLayoutConstraint]()
        let vertical = NSLayoutConstraint.constraints(withVisualFormat: "V:|-(0)-[contentView]-(0)-|", options: [], metrics: nil, views: views)
        allConstraints += vertical
        let horizontal = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(0)-[contentView(==superview)]-(0)-|", options: [], metrics: nil, views: views)
        allConstraints += horizontal
        NSLayoutConstraint.activate(allConstraints)

        alwaysBounceVertical = true
        backgroundColor = .clear
        clipsToBounds = false
        delegate = self

        bottomLayer.backgroundColor = self.content.backgroundColor?.cgColor
        layer.addSublayer(bottomLayer)


    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let bottomLayer = CALayer()

    override func layoutSubviews() {
        super.layoutSubviews()

        let newFrame = CGRect(x: 0, y: content.frame.size.height, width: content.frame.size.width, height: 1000)


        if newFrame != bottomLayer.frame {
            content.roundCorners(corners: [.topLeft, .topRight], radius: 12.0)
            bottomLayer.frame = newFrame
        }

        //print("layouted")
    }

    func open() {
        // print("opened")
        moveToClosed()

        setNeedsLayout()
        layoutIfNeeded()


//
//
//        print(content.frame.size.width)
//        print(frame.size.width)

        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: {
            self.moveToBottom()
        })
    }

    private func moveToClosed() {
        let contentheight = middleHeight()

        if let sView = superview {
            var f = frame
            f.size.height = contentheight
            f.size.width = sView.frame.size.width
            f.origin.y = sView.frame.size.height
            frame = f
        }
    }

    fileprivate func moveToBottom() {
        if let sView = superview {
            // First execution forces layout or something, without this line middleHeight returns worng height
            content.systemLayoutSizeFitting(CGSize(width: frame.size.width, height: 40)).height
            let contentheight = middleHeight()

            var f = frame
            f.size.height = contentheight
            f.size.width = sView.frame.size.width

            f.origin.y = sView.frame.size.height - contentheight  - (self.superview?.superview?.safeAreaInsets.bottom ?? 0)
            frame = f
        }
    }


    private func outOfOffset() -> Bool {
        let contentheight = middleHeight()
        if let sView = superview {
            var f = frame
            f.size.height = contentheight
            let shouldBeY = sView.frame.size.height - contentheight
            let itIsY = frame.origin.y

            if itIsY - shouldBeY > 70 {
                return true
            }
        }

        return false
    }


    var isViewDragging = false

    var offsetReads: [(date: Date, offset:CGFloat)] = []

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isViewDragging == false {
            return
        }
        cardDidScroll()
    }

    func cardDidScroll() {
        let contentheight = self.middleHeight()
        if contentOffset.y < 0  || (frame.origin.y > (superview?.frame.size.height ?? 0) - contentheight) {
            var f = frame
            f.origin.y -= contentOffset.y
            frame = f

        }

        let date = Date()
        offsetReads.append((date: date, offset: frame.origin.y))
        //print(date)

        if offsetReads.count > 40 {
            offsetReads.removeFirst()
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        isViewDragging = false
        let currentDate = Date()
        //print(currentDate)
        let revelentTimestamps = offsetReads.filter{abs($0.date.timeIntervalSince1970 - currentDate.timeIntervalSince1970)<0.1}


        offsetReads = []

        let speed: CGFloat
        if let firstTimestamp = revelentTimestamps.first {
            let t = abs(firstTimestamp.date.timeIntervalSince1970 - currentDate.timeIntervalSince1970)
            let s = frame.origin.y - firstTimestamp.offset
            speed = s/CGFloat(t)
        } else {
            speed = 0
        }

        cardWillEndDragging(with: speed, targetContentOffset: targetContentOffset)
    }

    func cardWillEndDragging(with speed: CGFloat, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if outOfOffset() || abs(speed) > closingSpeed {
            close() {
                self.card.events.closeCardAction.send(.userGesture)
            }
        } else {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                self.moveToBottom()
            })
        }

    }

    func close(completion:(()-> Void)? = nil) {
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            let contentheight = self.middleHeight()
            if let sView = self.superview {
                var f = self.frame
                f.size.height = contentheight
                f.origin.y = sView.frame.size.height + (self.superview?.superview?.safeAreaInsets.bottom ?? 0)
                self.frame = f

                //self.card.events.closeCardAction.send()
            }
        }, completion: { finished in

            completion?()
            self.removeFromSuperview()
        })
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isViewDragging = true

        let date = Date()
        offsetReads.append((date: date, offset: frame.origin.y))
    }
}


class UIKitFullScreenCardView<Content>: UIKitCardView<Content> where Content: View {
    let openedHeight: CGFloat
    private var viewState = ViewState.middle
    override func middleHeight() -> CGFloat { openedHeight }
    enum ViewState {case willClose, fullScreen, middle}

    private enum ViewNextState{case same, up, down}

    private func nextThereshold() -> ViewState {
        if let sView = superview {
            let shouldBeY: CGFloat
            switch viewState {
            case .fullScreen:
                shouldBeY = topSpace()
            case .middle:
                shouldBeY = sView.frame.size.height - openedHeight
            default:
                shouldBeY = sView.frame.size.height
            }

            let itIsY = frame.origin.y

            let next: ViewNextState


            if  shouldBeY - itIsY > thereshold {
                next = .up
            } else if shouldBeY - itIsY < -1 * thereshold {
                next = .down
            } else {
                next = .same
            }

            switch viewState {
            case .fullScreen:
                if next == .down {
                    return .middle
                }
            case .middle:
                if next == .down {
                    return .willClose
                } else if next == .up {
                    return .fullScreen
                }
            default:
                break
            }
        }

        return viewState
    }

    init(card: Card, content: Content, openedHeight: CGFloat) {
        self.openedHeight = openedHeight
        super.init(card: card, content: content)
        clipsToBounds = true
        alwaysBounceVertical = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cardWillEndDragging(with speed: CGFloat, targetContentOffset: UnsafeMutablePointer<CGPoint>) {

        let nextViewState = nextThereshold()

        if nextViewState == .fullScreen || ((viewState == .middle) && (speed < -closingSpeed)) {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: {
                if let sView = self.superview {
                    var f = self.frame
                    f.size.height = sView.frame.size.height - self.topSpace()
                    f.origin.y = self.topSpace()
                    self.frame = f

                    self.card.events.topSpace.send(self.frame.origin.y - self.topSpace())
                }
            })
        } else if nextViewState == .willClose || ((viewState == .middle) && (speed > closingSpeed)) {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: {
                if let sView = self.superview {
                    var f = self.frame
                    f.origin.y = sView.frame.size.height + (self.superview?.superview?.safeAreaInsets.bottom ?? 0)
                    self.frame = f
                    self.card.events.topSpace.send(self.frame.origin.y - self.topSpace())
                }
            }, completion: { finished in
                self.card.events.cardDidClosed.send(.userGesture)
                self.removeFromSuperview()
            })
        } else if nextViewState == .middle || ((viewState == .fullScreen) && speed > closingSpeed) {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction], animations: {
                if let sView = self.superview {
                    var f = self.frame
                    f.origin.y = sView.frame.size.height - self.openedHeight
                    f.size.height = sView.frame.size.height
                    self.frame = f

                    self.card.events.topSpace.send(self.frame.origin.y - self.topSpace())
                }
            })
        }



        if viewState != .fullScreen {
            targetContentOffset.pointee = CGPoint(x: 0, y: 0)
        }

        print ("finifhed with offset \(contentOffset)")

        viewState = nextViewState

        if viewState != .fullScreen {
            showsVerticalScrollIndicator = false
        } else {
            showsVerticalScrollIndicator = true
        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        card.events.contentOffset.send(contentOffset.y)
    }

    override func cardDidScroll() {
        let contentheight = middleHeight()
        if (contentOffset.y < 0  || frame.origin.y > topSpace()) {
            var f = frame
            f.origin.y -= contentOffset.y

            if f.origin.y < topSpace() {
                f.origin.y = topSpace()
            }

            frame = f

            contentOffset.y = 0

            self.card.events.topSpace.send(frame.origin.y - topSpace())
            //print(frame.origin.y - topSpace())
            self.showsVerticalScrollIndicator = true
        }

        offsetReads.append((date: Date(), offset: frame.origin.y))

        if offsetReads.count > 40 {
            offsetReads.removeFirst()
        }
    }

    func topSpace() -> CGFloat {
        let top = superview?.superview?.superview?.safeAreaInsets.top ?? 0
        let bottomX = superview?.superview?.superview?.safeAreaInsets.bottom ?? 0
        // TODO I do not know why i have to add 7 if no curvy screen
        let bottom = bottomX == 0 ? 7 : bottomX
        return top - bottom + 65 - 21 + 34 + 6
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView)
        self.showsVerticalScrollIndicator = false
//        var f = frame
//        f.size.height = 1000
//        frame = f
    }

    // almost exact copy from parent class expept it has bigger content 
    fileprivate override func moveToBottom() {
        if let sView = superview {
            // First execution forces layout or something, without this line middleHeight returns worng height
            content.systemLayoutSizeFitting(CGSize(width: frame.size.width, height: 40)).height
            let contentheight = middleHeight()

            var f = frame
            f.size.height = contentheight + 1000
            f.size.width = sView.frame.size.width

            f.origin.y = sView.frame.size.height - contentheight  - (self.superview?.superview?.safeAreaInsets.bottom ?? 0)
            frame = f
        }
    }
}
