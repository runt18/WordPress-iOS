import UIKit
import WordPressShared

class PlanDetailViewController: UIViewController {
    var plan: Plan!
    var siteID: Int!
    
    private let cellIdentifier = "PlanFeatureListItem"
    
    private let tableViewHorizontalMargin: CGFloat = 24.0
    private let planImageDropshadowRadius: CGFloat = 3.0
    
    var isActivePlan = false
    
    private var tableViewModel = ImmuTable.Empty {
        didSet {
            tableView?.reloadData()
        }
    }
    var viewModel: PlanFeatureViewModel = .Loading {
        didSet {
            bindViewModel(viewModel)
            updateNoResults()
        }
    }
    
    private let noResultsView = WPNoResultsView()
    
    func updateNoResults() {
        if let noResultsViewModel = viewModel.noResultsViewModel {
            showNoResults(noResultsViewModel)
        } else {
            hideNoResults()
        }
    }
    func showNoResults(viewModel: WPNoResultsView.Model) {
        noResultsView.bindViewModel(viewModel)
        if noResultsView.isDescendantOfView(tableView) {
            noResultsView.centerInSuperview()
        } else {
            tableView.addSubviewWithFadeAnimation(noResultsView)
        }
    }
    
    func hideNoResults() {
        noResultsView.removeFromSuperview()
    }

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var planImageView: UIImageView!
    @IBOutlet weak var dropshadowImageView: UIImageView!
    @IBOutlet weak var planTitleLabel: UILabel!
    @IBOutlet weak var planDescriptionLabel: UILabel!
    @IBOutlet weak var planPriceLabel: UILabel!
    @IBOutlet weak var purchaseButton: UIButton!
    @IBOutlet weak var separator: UIView!

    private lazy var currentPlanLabel: UIView = {
        let label = UILabel()
        label.font = WPFontManager.systemSemiBoldFontOfSize(13.0)
        label.textColor = WPStyleGuide.validGreen()
        label.text = NSLocalizedString("Current Plan", comment: "").uppercaseStringWithLocale(NSLocale.currentLocale())
        label.translatesAutoresizingMaskIntoConstraints = false

        // Wrapper view required for spacing to work out correctly, as the header stackview
        // is baseline-based, and so acts differently for a label vs view.
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        wrapper.pinSubviewToAllEdges(label)
        
        return wrapper
    }()
    
    @IBOutlet weak var headerInfoStackView: UIStackView!

    class func controllerWithPlan(plan: Plan, siteID: Int, isActive: Bool) -> PlanDetailViewController {
        let storyboard = UIStoryboard(name: "Plans", bundle: NSBundle.mainBundle())
        let controller = storyboard.instantiateViewControllerWithIdentifier(NSStringFromClass(self)) as! PlanDetailViewController
        
        controller.plan = plan
        controller.siteID = siteID
        controller.isActivePlan = isActive
        
        return controller
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureAppearance()
        configureTableView()
        updateNoResults()
    }
    
    private func configureAppearance() {
        planTitleLabel.textColor = WPStyleGuide.darkGrey()
        planDescriptionLabel.textColor = WPStyleGuide.grey()
        planPriceLabel.textColor = WPStyleGuide.grey()
        
        purchaseButton.tintColor = WPStyleGuide.wordPressBlue()
        
        dropshadowImageView.backgroundColor = UIColor.whiteColor()
        configurePlanImageDropshadow()
        
        separator.backgroundColor = WPStyleGuide.greyLighten30()
    }
    
    private func configureTableView() {
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 80.0

        // This is required to remove the extra grouped tableview
        // padding at the top of the tableview
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 1))
    }
    
    private func configurePlanImageDropshadow() {
        dropshadowImageView.layer.masksToBounds = false
        dropshadowImageView.layer.shadowColor = WPStyleGuide.greyLighten30().CGColor
        dropshadowImageView.layer.shadowOpacity = 1.0
        dropshadowImageView.layer.shadowRadius = planImageDropshadowRadius
        dropshadowImageView.layer.shadowOffset = .zero
        dropshadowImageView.layer.shadowPath = UIBezierPath(ovalInRect: dropshadowImageView.bounds).CGPath
    }
    
    lazy var paddingView = UIView()
    
    private func populateHeader(plan: Plan, isActivePlan: Bool) {
        planImageView.image = plan.image
        planTitleLabel.text = plan.fullTitle
        planDescriptionLabel.text = plan.description
        planPriceLabel.text = priceDescriptionForPlan(plan)
        
        if isActivePlan {
            purchaseButton.removeFromSuperview()
            headerInfoStackView.addArrangedSubview(currentPlanLabel)
        } else if plan.isFreePlan {
            purchaseButton.removeFromSuperview()
            headerInfoStackView.addArrangedSubview(paddingView)
        }
    }
    
    func bindViewModel(viewModel: PlanFeatureViewModel) {
        self.tableViewModel = viewModel.tableViewModel
        title = plan.title
        populateHeader(plan, isActivePlan: isActivePlan)
    }
    
    // TODO: Prices should always come from StoreKit
    // @frosty 2016-02-04
    private func priceDescriptionForPlan(plan: Plan) -> String? {
        switch plan.slug {
        case "free":
            return "Free for life"
        case "premium":
            return "$99.99 per year"
        case "business":
            return "$299.99 per year"
        default:
            return nil
        }
    }
    
    //MARK: - IBActions
    
    @IBAction private func purchaseTapped() {
        guard let identifier = plan.productIdentifier else {
            return
        }
        purchaseButton.selected = true
        let store = StoreKitStore()
        store.getProductsWithIdentifiers(
            Set([identifier]),
            success: { products in
                StoreKitCoordinator.instance.purchasePlan(self.plan, product: products[0], forSite: self.siteID)
            },
            failure: { error in
                DDLogSwift.logError("Error fetching Store products: \(error)")
                self.purchaseButton.selected = false
        })
    }
    
    enum PlanFeatureViewModel {
        case Loading
        case Ready(Plan)
        case Error(String)
        
        var tableViewModel: ImmuTable {
            switch self {
            case .Loading, .Error(_):
                return ImmuTable.Empty
            case .Ready(let plan):
                guard let groups = PlanFeatureGroup.groupsForPlan(plan) else {
                    return ImmuTable.Empty
                }
                
                return ImmuTable(sections: groups.map { group in
                    let features = group.slugs.flatMap { PlanService<StoreKitStore>.featureForPlan(plan, withSlug: $0) }
                    let rows: [ImmuTableRow] = features.map({ feature in
                        return FeatureItemRow(title: feature.title, description: feature.description, iconURL: feature.iconURL)
                    })
                    return ImmuTableSection(headerText: group.title, rows: rows, footerText: nil)
                })
            }
        }
        
        var noResultsViewModel: WPNoResultsView.Model? {
            switch self {
            case .Loading:
                return WPNoResultsView.Model(
                    title: NSLocalizedString("Loading Plan...", comment: "Text displayed while loading plans details")
                )
            case .Ready(_):
                return nil
            case .Error(_):
                return WPNoResultsView.Model(
                    title: NSLocalizedString("Oops", comment: ""),
                    message: NSLocalizedString("There was an error loading the plan", comment: ""),
                    buttonTitle: NSLocalizedString("Contact support", comment: "")
                )
            }
        }
    }
}

// MARK: Table View Data Source / Delegate
extension PlanDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return tableViewModel.sections.count
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableViewModel.sections[section].rows.count
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let row = tableViewModel.rowAtIndexPath(indexPath)
        let cell = tableView.dequeueReusableCellWithIdentifier(row.reusableIdentifier, forIndexPath: indexPath)
        
        row.configureCell(cell)
        
        return cell
    }
    
    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        guard let cell = cell as? FeatureItemCell else { return }
        
        let separatorInset: CGFloat = 15
        let isLastCellInSection = indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1
        let isLastSection = indexPath.section == self.numberOfSectionsInTableView(tableView) - 1
        
        // The separator for the last cell in each section has no insets, 
        // except for in the last section, where there's no separator at all.
        if isLastCellInSection {
            if isLastSection {
                cell.separator.hidden = true
            } else {
                cell.separatorInset = UIEdgeInsetsZero
            }
        } else {
            cell.separatorInset = UIEdgeInsets(top: 0, left: separatorInset, bottom: 0, right: separatorInset)
        }
    }
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return tableViewModel.sections[section].headerText
    }
    
    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if let title = self.tableView(tableView, titleForHeaderInSection: section) where !title.isEmpty {
            let header = WPTableViewSectionHeaderFooterView(reuseIdentifier: nil, style: .Header)
            header.title = title
            return header
        } else {
            return nil
        }
    }
}

class FeatureItemCell: WPTableViewCell {
    @IBOutlet weak var featureIconImageView: UIImageView!
    @IBOutlet weak var featureTitleLabel: UILabel!
    @IBOutlet weak var featureDescriptionLabel: UILabel!
    @IBOutlet weak var separator: UIView!
    @IBOutlet var separatorEdgeConstraints: [NSLayoutConstraint]!
    
    override var separatorInset: UIEdgeInsets {
        didSet {
            for constraint in separatorEdgeConstraints {
                if constraint.firstAttribute == .Leading {
                    constraint.constant = separatorInset.left
                } else if constraint.firstAttribute == .Trailing {
                    constraint.constant = separatorInset.right
                }
            }
            
            separator.layoutIfNeeded()
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()

        layoutMargins = UIEdgeInsetsZero
        
        separator.backgroundColor = WPStyleGuide.greyLighten30()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        separator.hidden = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // This is required to fix an issue where only the first line of text would
        // is displayed on the iPhone 6(s) Plus due to a fractional Y position.
        featureDescriptionLabel.frame = CGRectIntegral(featureDescriptionLabel.frame)
    }
}

struct FeatureItemRow : ImmuTableRow {
    static let cell = ImmuTableCell.Class(FeatureItemCell)
    
    let title: String
    let description: String
    let iconURL: NSURL
    let action: ImmuTableAction? = nil
    
    func configureCell(cell: UITableViewCell) {
        guard let cell = cell as? FeatureItemCell else { return }
        
        cell.featureTitleLabel?.text = title
        
        if let featureDescriptionLabel = cell.featureDescriptionLabel {
            cell.featureDescriptionLabel?.attributedText = attributedDescriptionText(description, font: featureDescriptionLabel.font)
        }
        
        cell.featureIconImageView?.setImageWithURL(iconURL, placeholderImage: nil)
        
        cell.featureTitleLabel.textColor = WPStyleGuide.darkGrey()
        cell.featureDescriptionLabel.textColor = WPStyleGuide.grey()
        WPStyleGuide.configureTableViewCell(cell)
    }
    
    private func attributedDescriptionText(text: String, font: UIFont) -> NSAttributedString {
        let lineHeight: CGFloat = 18
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.minimumLineHeight = lineHeight
        
        let attributedText = NSMutableAttributedString(string: text, attributes: [NSParagraphStyleAttributeName: paragraphStyle, NSFontAttributeName: font])
        return attributedText
    }
}
