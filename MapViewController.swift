import UIKit
import MapKit
import AVFoundation
import QuartzCore
import Promise


class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate, HasSlideInErrMsg, HasMsgBox, UIPopoverPresentationControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, EditPinDelegate, ViewPinsetNameChangedDelegate, OnboardingViewDelegate, RectangleSearchOverlayDelegate, AddPhotoViewDelegate, CustomCalloutDelegate {
    
    var locationManager: CLLocationManager = CLLocationManager()
    var clickedPinAnnotation: MKAnnotationWithExtraInfo?
    var buttonsOnLeftOrRight = LeftOrRight.right
    var buttonsUpOrDown = UpOrDown.down
    var slideInCallout: CustomCallout?
    var errorMsgCallout: ErrorMsgView?
    var pinsetsArray : [SinglePinset] = []
    var frameCalloutOffscreen: CGRect?
    var frameCalloutOnscreen: CGRect?
    var lastPin: SinglePin?
    var lastPinset: SinglePinset?
    var myRectangleSearchOverlay: RectangleSearchOverlay?
    var clearViewBehindButtons: UIView?
    var coordForSearchTopLeft: CLLocationCoordinate2D?
    var coordForSearchBottomRight: CLLocationCoordinate2D?
    var drawnCoordinatesInOverlay: [CLLocationCoordinate2D] = []
    var touchLocationOnMap: CGPoint?
    var newButtonXConstraintRightSide: NSLayoutConstraint!
    var newButtonXConstraintLeftSide: NSLayoutConstraint!
    var newButtonXConstraintLeftSideOffscreen: NSLayoutConstraint!
    var newButtonXConstraintRightSideOffscreen: NSLayoutConstraint!
    var layersBtnConstraintExpanded: NSLayoutConstraint!
    var layersBtnConstraintCollapsed: NSLayoutConstraint!
    var searchBtnConstraintExpanded: NSLayoutConstraint!
    var searchBtnConstraintCollapsed: NSLayoutConstraint!
    var gpsBtnConstraintExpanded: NSLayoutConstraint!
    var gpsBtnConstraintCollapsed: NSLayoutConstraint!
    var settingsBtnConstraintExpanded: NSLayoutConstraint!
    var settingsBtnConstraintCollapsed: NSLayoutConstraint!
    var helpBtnConstraintExpanded: NSLayoutConstraint!
    var helpBtnConstraintCollapsed: NSLayoutConstraint!
    var addPhotoView: AddPhotoView?
    var modalCurtain: UIView?
    var addPhotoTimer: Timer?
    let imagePicker = UIImagePickerController() //just have 1 instance of this for the form's lifetime.
    var onboardingView: OnboardingView!
    var curtainForOnboarding: UIView!
    var actionAfterFindingLocation: ActionAfterFindingLocation = ActionAfterFindingLocation.noAction
    var promiseForLocationRequest: Promise<String>?
    var lastUpdatedLocation: CLLocation?
    var legalLabelOriginalLocation: CGRect?
    
    @IBOutlet weak var newButton: UIButton!
    @IBOutlet weak var myMapView: MKMapView!
    @IBOutlet weak var myLayersButton: RoundButton!
    @IBOutlet weak var gpsLocateButton: RoundButton!
    @IBOutlet weak var settingsButton: RoundButton!
    @IBOutlet weak var helpButton: RoundButton!
    @IBOutlet weak var mySearchButton: RoundButton!
    @IBOutlet weak var nextPinsetLabel: UILabel!
    @IBOutlet weak var nextPinsetLabelContainerView: UIView!
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.imagePicker.delegate=self //you need both UIImagePickerControllerDelegate and UINavigationControllerDelegate or this will give error

        self.curtainForOnboarding = self.createCurtainForOnboarding()
        self.onboardingView = self.createOnboardingView(delegate: self)
        
        //this view has to be there before swipeuoordown gets called, which is why code is up here
        //I noticed that when the buttons are expanded, and I swipe down, frequently the swipe moves the map
        //instead. I had the idea to put a clear-background uiview behind them in expanded mode and put a
        //swipe-down recognizer on it to prevent accidental swipes on the map
        let clearSwiperView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        clearSwiperView.backgroundColor = UIColor.clear
        
        let clearViewWipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        clearViewWipeDown.direction = UISwipeGestureRecognizer.Direction.down
        clearSwiperView.addGestureRecognizer(clearViewWipeDown)
        
        let clearViewWipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        clearViewWipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        clearSwiperView.addGestureRecognizer(clearViewWipeLeft)

        let clearViewWipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        clearViewWipeRight.direction = UISwipeGestureRecognizer.Direction.right
        clearSwiperView.addGestureRecognizer(clearViewWipeRight)

        self.clearViewBehindButtons = clearSwiperView
        //**add it to the view after the buttons have gone in, so i can insert it at the correct z-order
        
        //New Button
        //-------------------------------------------
        self.newButton.translatesAutoresizingMaskIntoConstraints = false //per raywenderlich, "this tells the view to use autolayout rather than frames. IB does this automatically, but if you're using code you need to set it."
        //!!!These 2 anchors are intentionally conflicting, but the right side is set to higher priority. I flip-flop them
        //to move the buttons to the other side.
        //you have to set it to 999 so it's mutable. if  it's set to 1000, it's locked in place.
        self.newButtonXConstraintRightSide = self.newButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20.0)
        self.newButtonXConstraintRightSide.priority = UILayoutPriority(rawValue: 999.0)
        self.newButtonXConstraintRightSide.isActive = true
        
        self.newButtonXConstraintLeftSide = self.newButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20.0)
        self.newButtonXConstraintLeftSide.priority = UILayoutPriority(rawValue: 250.0)
        self.newButtonXConstraintLeftSide.isActive = true
        
        //these are only used when you're drawing a polygon; it hides them offscreen.
        self.newButtonXConstraintRightSideOffscreen = self.newButton.leadingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: 0.0)
        self.newButtonXConstraintRightSideOffscreen.priority = UILayoutPriority(rawValue: 250.0)
        self.newButtonXConstraintRightSideOffscreen.isActive = true
        self.newButtonXConstraintLeftSideOffscreen = self.newButton.trailingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 0.0)
        self.newButtonXConstraintLeftSideOffscreen.priority = UILayoutPriority(rawValue: 250.0)
        self.newButtonXConstraintLeftSideOffscreen.isActive = true
        
        //I don't save these to vars b/c I don't change them programmatically. Note that you can add the "isActive" at the end to save a line.
        self.newButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20.0).isActive = true
        
        self.newButton.widthAnchor.constraint(equalToConstant: 56.0).isActive = true
        self.newButton.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        
        //Layers button
        //-------------------------------------------
        self.myLayersButton.translatesAutoresizingMaskIntoConstraints = false
        self.myLayersButton.centerXAnchor.constraint(equalTo: self.newButton.centerXAnchor).isActive = true
        self.myLayersButton.widthAnchor.constraint(equalToConstant: 56.0).isActive = true
        self.myLayersButton.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        
        //these are the conflicting ones, for expand and collapse. No need to track X b/c it tethers to the New Button via the 4 "centerXAnchor" above.
        //note that these constraints aren't tied to the storyboard via iboutlets. It's not like you say "newbutton.constraint = constraint".
        //It's actually the reverse--you says "constraint = "newbutton.bottomanchor", and then the constraint starts controlling the object's position.
        self.layersBtnConstraintCollapsed = self.myLayersButton.bottomAnchor.constraint(equalTo: self.newButton.bottomAnchor, constant: -5.0)
        self.layersBtnConstraintCollapsed.priority = UILayoutPriority(rawValue: 250.0)
        self.layersBtnConstraintCollapsed.isActive = true
        
        self.layersBtnConstraintExpanded = self.myLayersButton.bottomAnchor.constraint(equalTo: self.newButton.topAnchor, constant: -16.0)
        self.layersBtnConstraintExpanded.priority = UILayoutPriority(rawValue: 999.0)
        self.layersBtnConstraintExpanded.isActive = true

        //Search button
        //-------------------------------------------
        self.mySearchButton.translatesAutoresizingMaskIntoConstraints = false
        self.mySearchButton.centerXAnchor.constraint(equalTo: self.myLayersButton.centerXAnchor).isActive = true
        self.mySearchButton.widthAnchor.constraint(equalToConstant: 56.0).isActive = true
        self.mySearchButton.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        
        //these are the conflicting ones, for expand and collapse. No need to track X b/c it tethers to the New Button via the 4 "centerXAnchor" above.
        self.searchBtnConstraintCollapsed = self.mySearchButton.bottomAnchor.constraint(equalTo: self.myLayersButton.bottomAnchor, constant: -5.0)
        self.searchBtnConstraintCollapsed.priority = UILayoutPriority(rawValue: 250.0)
        self.searchBtnConstraintCollapsed.isActive = true
        
        self.searchBtnConstraintExpanded = self.mySearchButton.bottomAnchor.constraint(equalTo: self.myLayersButton.topAnchor, constant: -16.0)
        self.searchBtnConstraintExpanded.priority = UILayoutPriority(rawValue: 999.0)
        self.searchBtnConstraintExpanded.isActive = true
        
        //GPS button
        //-------------------------------------------
        self.gpsLocateButton.translatesAutoresizingMaskIntoConstraints = false
        self.gpsLocateButton.centerXAnchor.constraint(equalTo: self.mySearchButton.centerXAnchor).isActive = true
        self.gpsLocateButton.widthAnchor.constraint(equalToConstant: 56.0).isActive = true
        self.gpsLocateButton.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        
        //these are the conflicting ones, for expand and collapse. No need to track X b/c it tethers to the New Button via the 4 "centerXAnchor" above.
        self.gpsBtnConstraintCollapsed = self.gpsLocateButton.bottomAnchor.constraint(equalTo: self.mySearchButton.bottomAnchor, constant: -5.0)
        self.gpsBtnConstraintCollapsed.priority = UILayoutPriority(rawValue: 250.0)
        self.gpsBtnConstraintCollapsed.isActive = true
        
        self.gpsBtnConstraintExpanded = self.gpsLocateButton.bottomAnchor.constraint(equalTo: self.mySearchButton.topAnchor, constant: -16.0)
        self.gpsBtnConstraintExpanded.priority = UILayoutPriority(rawValue: 999.0)
        self.gpsBtnConstraintExpanded.isActive = true

        //Settings button
        //-------------------------------------------
        self.settingsButton.translatesAutoresizingMaskIntoConstraints = false
        self.settingsButton.centerXAnchor.constraint(equalTo: self.gpsLocateButton.centerXAnchor).isActive = true
        self.settingsButton.widthAnchor.constraint(equalToConstant: 40.0).isActive = true
        self.settingsButton.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        
        //these are the conflicting ones, for expand and collapse. No need to track X b/c it tethers to the New Button via the 4 "centerXAnchor" above.
        self.settingsBtnConstraintCollapsed = self.settingsButton.bottomAnchor.constraint(equalTo: self.gpsLocateButton.bottomAnchor, constant: -5.0)
        self.settingsBtnConstraintCollapsed.priority = UILayoutPriority(rawValue: 250.0)
        self.settingsBtnConstraintCollapsed.isActive = true
        
        self.settingsBtnConstraintExpanded = self.settingsButton.bottomAnchor.constraint(equalTo: self.gpsLocateButton.topAnchor, constant: -16.0)
        self.settingsBtnConstraintExpanded.priority = UILayoutPriority(rawValue: 999.0)
        self.settingsBtnConstraintExpanded.isActive = true

        //Help button
        //-------------------------------------------
        self.helpButton.translatesAutoresizingMaskIntoConstraints = false
        self.helpButton.centerXAnchor.constraint(equalTo: self.settingsButton.centerXAnchor).isActive = true
        self.helpButton.widthAnchor.constraint(equalToConstant: 40.0).isActive = true
        self.helpButton.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        
        //these are the conflicting ones, for expand and collapse. No need to track X b/c it tethers to the New Button via the 4 "centerXAnchor" above.
        self.helpBtnConstraintCollapsed = self.helpButton.bottomAnchor.constraint(equalTo: self.settingsButton.bottomAnchor, constant: -5.0)
        self.helpBtnConstraintCollapsed.priority = UILayoutPriority(rawValue: 250.0)
        self.helpBtnConstraintCollapsed.isActive = true
        
        self.helpBtnConstraintExpanded = self.helpButton.bottomAnchor.constraint(equalTo: self.settingsButton.topAnchor, constant: -16.0)
        self.helpBtnConstraintExpanded.priority = UILayoutPriority(rawValue: 999.0)
        self.helpBtnConstraintExpanded.isActive = true

        //@@@@@@@@@@@@@@@@@@@@

        //put the buttons down. They're expanded in storyboard, but put them back down.
        self.moveButtonsUpOrDown(moveTo: UpOrDown.down)
        
        self.myMapView.delegate = self
        self.locationManager.delegate = self
         
        //@@@@@@@@@@@@@
        //left swipe
        let button1SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button1SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.newButton.addGestureRecognizer(button1SwipeLeft)
        
        let button2SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button2SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.myLayersButton.addGestureRecognizer(button2SwipeLeft)

        let button3SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button3SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.mySearchButton.addGestureRecognizer(button3SwipeLeft)

        let button4SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button4SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.gpsLocateButton.addGestureRecognizer(button4SwipeLeft)
        
        let button5SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button5SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.settingsButton.addGestureRecognizer(button5SwipeLeft)
        
        let button6SwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedLeft(gesture:)))
        button6SwipeLeft.direction = UISwipeGestureRecognizer.Direction.left
        self.helpButton.addGestureRecognizer(button6SwipeLeft)
        
        //@@@@@@@@@@@@@
        //right swipe
        let button1SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button1SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.newButton.addGestureRecognizer(button1SwipeRight)
        
        let button2SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button2SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.myLayersButton.addGestureRecognizer(button2SwipeRight)

        let button3SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button3SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.mySearchButton.addGestureRecognizer(button3SwipeRight)

        let button4SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button4SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.gpsLocateButton.addGestureRecognizer(button4SwipeRight)
        
        let button5SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button5SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.settingsButton.addGestureRecognizer(button5SwipeRight)
        
        let button6SwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedRight(gesture:)))
        button6SwipeRight.direction = UISwipeGestureRecognizer.Direction.right
        self.helpButton.addGestureRecognizer(button6SwipeRight)
        
        //@@@@@@@@@@@@@
        //up swipe
        //I only need an up swipe for the 1st button b/c it's the only one that you can swipe up.
        let button1SwipeUp = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedUp(gesture:)))
        button1SwipeUp.direction = UISwipeGestureRecognizer.Direction.up
        self.newButton.addGestureRecognizer(button1SwipeUp)
        
        //@@@@@@@@@@@@@
        //down swipe
        let button1SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button1SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.newButton.addGestureRecognizer(button1SwipeDown)
        
        let button2SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button2SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.myLayersButton.addGestureRecognizer(button2SwipeDown)

        let button3SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button3SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.mySearchButton.addGestureRecognizer(button3SwipeDown)

        let button4SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button4SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.gpsLocateButton.addGestureRecognizer(button4SwipeDown)
        
        let button5SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button5SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.settingsButton.addGestureRecognizer(button5SwipeDown)
        
        let button6SwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.buttonsSwipedDown(gesture:)))
        button6SwipeDown.direction = UISwipeGestureRecognizer.Direction.down
        self.helpButton.addGestureRecognizer(button6SwipeDown)
        
        //this is to place a pin at that location.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.addPinAtPressLocation(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        self.myMapView.addGestureRecognizer(longPress)
        
        //code for the slide-in callout
        //*******************************************
        //from https://stackoverflow.com/questions/4754392/uiview-with-rounded-corners-and-drop-shadow
        //in order to get the dropshadow to work properly, I need to make a transparent base view, which the drop shadow applies to,
        //and then add the nib to it as a subview. The problem is caused by "clipstobounds". If I set this to true, the dropshadow gets
        //clipped off. If I set this to false, the dropshadow appears, but the blue title bar at the top doesn't get its little pointed corners
        //clipped off, and they appear beyond the nib's border.
        //Therefore, the base view has clips to bounds set to false, and has a clear color so it's essentially invisible, but will have the drop shadow on it.
        //Within that is a container view that will have the border--and its clips to bounds is true, so it will properly round off/truncate the title bar
        //within it.
        
        //first get the nib. I need to get this before the base view so I have the frame set, b/c the frame size comes from the nib.
        let nibs = Bundle.main.loadNibNamed("CustomCallout", owner: nil, options: nil)
        let calloutNib = nibs?[0] as! CustomCallout
        self.frameCalloutOffscreen = CGRect(x: 0, y: UIScreen.main.bounds.height, width: UIScreen.main.bounds.width, height: calloutNib.frame.height)
        self.frameCalloutOnscreen = CGRect(x: 0, y: UIScreen.main.bounds.height - calloutNib.frame.height, width: UIScreen.main.bounds.width, height: calloutNib.frame.height)
        calloutNib.frame = self.frameCalloutOffscreen!
        calloutNib.delegate = self
        
        calloutNib.isUserInteractionEnabled = true
        // add the drop shadow to the hidden base view
        calloutNib.layer.shadowColor = UIColor.darkGray.cgColor
        calloutNib.layer.shadowOffset = CGSize(width: 0, height: -3)
        calloutNib.layer.shadowOpacity = 0.7
        self.slideInCallout = calloutNib
        self.view.addSubview(self.slideInCallout!)
        
        //now create the error message slider. I put this in a protocol b/c I use it on multiple VCs.
        self.errorMsgCallout = instantiateSlideInErrMsg()
        self.view.addSubview(self.errorMsgCallout!)

        //put the clear view just above the map and below the buttons. This is the z-order.
        self.view.insertSubview(self.clearViewBehindButtons!, aboveSubview: self.myMapView)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.SVProgressHUDDidDisappear, object: nil, queue: nil) { notif in
            //See Notes.swift about SVProgressHUD about why I did it this way.
            if let funcToRun = GlobalFuncs.funcToRunAfterHidingHudHourglass {
                funcToRun()
            }
        }
        
        //this is for the addPhoto modal
        //@@@@@@@@@@@@@@@
        let addPhotoNibs = Bundle.main.loadNibNamed("AddPhotoView", owner: nil, options: nil)
        let addPhotoNib = addPhotoNibs?[0] as! AddPhotoView
        
        addPhotoNib.delegate = self
        
        let scrHt = UIScreen.main.bounds.height
        let scrWd = UIScreen.main.bounds.width
        let nibHt = addPhotoNib.frame.height
        let nibWd = addPhotoNib.frame.width
        
        let onscreenY = (scrHt - nibHt) / 2
        let x = (scrWd - nibWd) / 2
        addPhotoNib.onscreenFrame = CGRect(x: x, y: onscreenY, width: nibWd, height: nibHt)
        addPhotoNib.offscreenFrame = CGRect(x: x, y: scrHt, width: nibWd, height: nibHt)
        addPhotoNib.frame = addPhotoNib.offscreenFrame!
        calloutNib.isUserInteractionEnabled = true
        self.addPhotoView = addPhotoNib
        self.view.addSubview(self.addPhotoView!)

        let curtainView = UIView(frame: CGRect(x: 0, y: 0, width: scrWd, height: scrHt))
        curtainView.backgroundColor = UIColor.black
        curtainView.alpha = 0.66
        self.modalCurtain = curtainView
        //@@@@@@@@@@@@@@@@@

        //If have an either/or here so when I close the onboardingview, I can do the first-time zoom.
        if SqlTalker.getSetting(setting: "showHelpNextTime") == "yes" {
            self.openOnboardingView()
            SqlTalker.updateSetting(setting: "showHelpNextTime", newVal: "no")
        }

        //move buttons left if that's how they were before.
        if SqlTalker.getSetting(setting: "buttonsLeftOrRight") == "left" {
            self.buttonsOnLeftOrRight = LeftOrRight.left
            self.moveButtonsLeftOrRight()
        }
        
        //this if for the little "Legal" hyperlink in the lower-left corner.
        //this has to be at the very end or it sometimes errors out and says the subview isn't available.
        if self.myMapView.subviews.count > 1 {
            self.legalLabelOriginalLocation = self.myMapView.subviews[1].frame
        }
        
        //I refresh the pins in viewWillAppear, not here.
    }
    
    @IBAction func addPinClicked(_ sender: AnyObject) {
        
        Sound.play(file: "click.wav")
        
        GlobalFuncs.showHudHourglass(msg: nil)
        
        self.checkIfLocatServicesEnabled()
            .then(self.initiateLocationRequest) //there is a branch here that has to ask for permission, which hides and re-shows the hourglass
            .then(self.getCurrentLocationForPinAdd)
            .then(self.addPinAtCoordinate)
            .then({ (dummyString: String) in
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    self.showPhotoModal()
                })
            })
            .catch({ (err: Error) in
                self.promiseForLocationRequest = nil
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    self.locationError(locationErrorPacketAsError: err)
                })
            })
    }
    
    func getCurrentLocationForPinAdd(dummyString: String) -> Promise<CLLocationCoordinate2D> {

        //need to blank out the promise so I don't call it again from "didUpdateLocations" (which gets called on startup)
        self.promiseForLocationRequest = nil
        
        return Promise {resolve, reject in

            if let userLocation = self.locationManager.location?.coordinate {
                resolve(userLocation)
            }
            else if let userLocation = self.lastUpdatedLocation {
                    resolve(userLocation.coordinate)
            }
            else {
                let errPacket = LocationErrorPacket(locationErrorType: LocationErrorType.errorFromDelegate, errmsg: "Cannot get location".jtLocalize())
                reject(errPacket)
            }
        }
    }
    
    @IBAction func searchClicked(_ sender: Any) {
        let nibs = Bundle.main.loadNibNamed("RectangleSearchOverlay", owner: nil, options: nil)
        let newSearchScreen = nibs?[0] as! RectangleSearchOverlay
        newSearchScreen.frame = self.view.bounds
        newSearchScreen.isUserInteractionEnabled = true
        //by setting the transparency here instead of in IB, it doesn't apply to the buttons
        //inside the view. Not sure why, but it's handy b/c I don't want the buttons semi-transparent.
        //found this tip on SO.
        self.myRectangleSearchOverlay?.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        self.myRectangleSearchOverlay = newSearchScreen
        self.myRectangleSearchOverlay?.delegate = self
        self.view.addSubview(newSearchScreen)

        self.moveButtonsOnOrOffscreen()
        self.nextPinsetLabelContainerView.isHidden = true
    }
    
    @objc func addPinAtPressLocation(_ tapRecognizer: UITapGestureRecognizer) {
        
        if tapRecognizer.state != UIGestureRecognizer.State.began {
            return
        }
        
        self.touchLocationOnMap = tapRecognizer.location(in: self.myMapView)
        
        Sound.play(file: "click.wav")
        
        GlobalFuncs.showHudHourglass(msg: nil)
        
        self.checkIfLocatServicesEnabled()
            .then(self.initiateLocationRequest) //there is a branch here that has to ask for permission, which hides and re-shows the hourglass
            .then({ (dummyString: String) in
                return Promise {resolve, reject in
                    //get the location of the longpress
                    let locationCoordinate = self.myMapView.convert(self.touchLocationOnMap!, toCoordinateFrom: self.myMapView)
                    resolve(locationCoordinate)
                }
            })
            .then(self.addPinAtCoordinate)
            .then({ (dummyString: String) in
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    self.showPhotoModal()
                })
            })
            .catch({ (err: Error) in
                self.promiseForLocationRequest = nil
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    self.locationError(locationErrorPacketAsError: err)
                })
            })
    }
    
    @IBAction func layersClicked(_ sender: Any) {
        self.performSegue(withIdentifier: "ShowLayersSegue", sender: nil)
    }
    
    @IBAction func helpClicked(_ sender: Any) {

        self.openOnboardingView()
    }
    
    func closePolygonSearchOverlay() {
        
        //this gets called when you click the Cancel button, whereas "removePolygonOverlay" gets called when you hit OK.
        
        self.myRectangleSearchOverlay?.removeFromSuperview()
        self.myRectangleSearchOverlay = nil
        
        let overlays = self.myMapView.overlays
        self.myMapView.removeOverlays(overlays)

        self.moveButtonsOnOrOffscreen()
        self.nextPinsetLabelContainerView.isHidden = false
    }
    
    @IBAction func settingsClicked(_ sender: Any) {
        self.performSegue(withIdentifier: "ShowSettingsSegue", sender: nil)
    }

    @IBAction func gpsClicked(_ sender: Any) {
        self.findMeOnMap(promptUserIfSettingDisabled: true, doZoomOutZoomInBeforeFinding: false)
    }
    
    func findMeOnMap(promptUserIfSettingDisabled:Bool, doZoomOutZoomInBeforeFinding:Bool) {
        
        GlobalFuncs.showHudHourglass(msg: "Finding your location".jtLocalize())
        self.checkIfLocatServicesEnabled()
            .then(self.initiateLocationRequest) //there is a branch here that has to ask for permission, which hides and re-shows the hourglass
            .then({ (dummyString: String) in

                return Promise {resolve, reject in

                    if let userLocation = self.locationManager.location {
                        resolve(userLocation)
                    }
                    else if let userLocation = self.lastUpdatedLocation {
                        resolve(userLocation)
                    }
                    else {
                        let errPacket = LocationErrorPacket(locationErrorType: LocationErrorType.errorFromDelegate, errmsg: "Cannot get location".jtLocalize())
                        reject(errPacket)
                    }

                }
            })
            .then({ (locat: CLLocation) in
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    
                    //when they click the gps button, I just want to move to the blue dot, not zoom in.
                    if !doZoomOutZoomInBeforeFinding {
                        self.myMapView.setCenter(locat.coordinate, animated: true)
                        return
                    }
                    
                    //for willAppear and the onboarding closing, I want to zoom out first; it looks weird when it pans when it's zoomed in.
                    
                    MKMapView.animate(withDuration: 0.7, animations: {
                        self.myMapView.setCenter(locat.coordinate, animated: true)
                    }, completion: { _ in
                        //this is b/c it looks better zoomed in on your general area (for ex, LA basin) than showing the entire US.
                        let viewRegion:MKCoordinateRegion = MKCoordinateRegion.init(center: self.myMapView.centerCoordinate, latitudinalMeters: 30000, longitudinalMeters: 30000)
                        let adjustedRegion:MKCoordinateRegion = self.myMapView.regionThatFits(viewRegion)
                        self.myMapView.setRegion(adjustedRegion, animated: true)
                    })
                })
            })
            .catch({ (err: Error) in
                self.promiseForLocationRequest = nil
                GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                    self.locationError(locationErrorPacketAsError: err)
                })
            })
    }

    override func viewDidAppear(_ animated: Bool) {
        moveLegalLabel()
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        moveLegalLabel()
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        moveLegalLabel()
    }
    
    func moveLegalLabel() {
        guard let legalRect = self.legalLabelOriginalLocation else {
            return
        }

        if self.myMapView.subviews.count == 1 {
            return
        }
        
        //from https://stackoverflow.com/questions/30735770/reposition-legal-label-mkattributionlabel
        

        let legalLabel = self.myMapView.subviews[1]
        
        //I need to check which side the buttons are on so I know where to move it to.
        let x = (self.buttonsOnLeftOrRight == .right) ?
            legalRect.minX :
            (self.view.frame.size.width - legalRect.minX - legalRect.width)
        let y = self.nextPinsetLabelContainerView.frame.minY - 15

        legalLabel.frame = CGRect(x: x, y: y,
                                  width: legalLabel.frame.size.width, height: legalLabel.frame.size.height)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        super.viewWillAppear(animated)
        
        //I unhide this in "viewWillDisappear"
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        
        //also hide the toolbar, which is added by the layers view.
        self.navigationController?.setToolbarHidden(true, animated: false)
        
        //this is to show/hide the location blue dot.
        if SqlTalker.getSetting(setting: "showLocationOnMap") == "yes" {
            self.myMapView.showsUserLocation = true
        } else {
            self.myMapView.showsUserLocation = false
        }
        
        //I need to clear out orphans in case a pinset has had its pins moved away from it.
        let orphansExisted = SqlTalker.deleteOrphanPinsets()
        if orphansExisted {
            self.showThisSlideInMsg(errMsg: "Removed empty pinset".jtLocalize(), errMsgIcon: ErrMsgIcon.warningTriangle)
        }
        
        //I do this here instead of viewDidLoad b/c I also need to update them in case I changed the name of a pin.
        self.chartAllMapPins()
        
        //hide the callout in case it was onscreen when I left the VC.
        self.slideInCallout!.frame = self.frameCalloutOffscreen!
        
        if let myLastPinset = self.lastPinset {
            let exists = SqlTalker.checkForExistenceOfPinsetName(nm: myLastPinset.pinsetName)
                
            if !exists || (exists && SqlTalker.doesPinsetHaveCloudID(pinsetName: myLastPinset.pinsetName) == true) {
                self.lastPinset = nil
                }
        }
        
        self.setNextOrPrevSetLabel()

        if !self.onboardingView.isDescendant(of: self.view) && self.pinsetsArray.count == 0 {
            self.findMeOnMap(promptUserIfSettingDisabled: false, doZoomOutZoomInBeforeFinding: true)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        super.viewWillDisappear(animated)
    }
    
    public func chartAllMapPins() {
        
        //remove all pins first
        self.myMapView.removeAnnotations(self.myMapView.annotations)
        
        var pushpinArray: [MKAnnotationWithExtraInfo] = []
        
        self.pinsetsArray = []
        
        self.pinsetsArray += SqlTalker.getLocalPinsetsSingleOrArray(singleOrArray: SingleOrArray.array, pinsetname: nil)
        self.pinsetsArray += SqlTalker.getWebsetsSingleOrArray(singleOrArray: SingleOrArray.array, cloudid: nil)

        for (index, set) in self.pinsetsArray.enumerated() {
            
            if set.show == "y" {
                
                for pin in set.pinArray {
                    let lat = Double(pin.lat)
                    let lng = Double(pin.lng)
                    
                    let myLoc = CLLocationCoordinate2D(latitude: lat!, longitude:lng!)
                    
                    let myNewPin = MKAnnotationWithExtraInfo(coordinate: myLoc, pinsetIndex: index, name: pin.pinName, desc: pin.desc)
                    
                    myNewPin.title = " " //this is only used for the callout when a new pin is created

                    pushpinArray.append(myNewPin)
                }
            }
        }
        
        self.myMapView.showAnnotations(pushpinArray, animated: true)
    }
    
    
    @objc func buttonsSwipedUp(gesture: UIGestureRecognizer) {
        if self.buttonsUpOrDown == UpOrDown.up {
            return
        }
        
        self.buttonsUpOrDown = UpOrDown.up
        self.moveButtonsUpOrDown(moveTo: UpOrDown.up)
    }
    
    @objc func buttonsSwipedDown(gesture: UIGestureRecognizer) {
        if self.buttonsUpOrDown == UpOrDown.down {
            return
        }
        
        self.buttonsUpOrDown = UpOrDown.down
        self.moveButtonsUpOrDown(moveTo: UpOrDown.down)
    }
    
    @objc func buttonsSwipedLeft(gesture: UIGestureRecognizer) {
        
        if self.buttonsOnLeftOrRight == LeftOrRight.left {
            return
        }
        
        self.buttonsOnLeftOrRight = LeftOrRight.left
        self.moveButtonsLeftOrRight()
        SqlTalker.updateSetting(setting: "buttonsLeftOrRight", newVal: "left")
    }
    
    
    @objc func buttonsSwipedRight(gesture: UIGestureRecognizer) {
        
        if self.buttonsOnLeftOrRight == LeftOrRight.right {
            return
        }
        
        self.buttonsOnLeftOrRight = LeftOrRight.right
        self.moveButtonsLeftOrRight()
        SqlTalker.updateSetting(setting: "buttonsLeftOrRight", newVal: "right")
    }
    
    func moveButtonsUpOrDown(moveTo: UpOrDown) {
        
        //Here's how I did this with the constraints:
        //I made 2 constraints for each button, one expanded and one collapsed. I gave higher priority to the expanded one (999). You can't use
        //1000 b/c that means required, and it won't let you change it. It will let you change 999 though. I set the collapsed to 250. I then
        //flip-flop them.
        //I don't include the addnewButton here b/c it doesn't change position for the up/down action
        let layersBtnConstraintExpandedPriority = self.layersBtnConstraintExpanded.priority
        let layersBtnConstraintCollapsedPriority = self.layersBtnConstraintCollapsed.priority
        let searchBtnConstraintExpandedPriority = self.searchBtnConstraintExpanded.priority
        let searchBtnConstraintCollapsedPriority = self.searchBtnConstraintCollapsed.priority
        let gpsBtnConstraintExpandedPriority = self.gpsBtnConstraintExpanded.priority
        let gpsBtnConstraintCollapsedPriority = self.gpsBtnConstraintCollapsed.priority
        let settingsBtnConstraintExpandedPriority = self.settingsBtnConstraintExpanded.priority
        let settingsBtnConstraintCollapsedPriority = self.settingsBtnConstraintCollapsed.priority
        let helpBtnConstraintExpandedPriority = self.helpBtnConstraintExpanded.priority
        let helpBtnConstraintCollapsedPriority = self.helpBtnConstraintCollapsed.priority
        
        //swap their priorities, which in essence reverses them
        self.layersBtnConstraintExpanded.priority = layersBtnConstraintCollapsedPriority
        self.layersBtnConstraintCollapsed.priority = layersBtnConstraintExpandedPriority
        self.searchBtnConstraintExpanded.priority = searchBtnConstraintCollapsedPriority
        self.searchBtnConstraintCollapsed.priority = searchBtnConstraintExpandedPriority
        self.gpsBtnConstraintExpanded.priority = gpsBtnConstraintCollapsedPriority
        self.gpsBtnConstraintCollapsed.priority = gpsBtnConstraintExpandedPriority
        self.settingsBtnConstraintExpanded.priority = settingsBtnConstraintCollapsedPriority
        self.settingsBtnConstraintCollapsed.priority = settingsBtnConstraintExpandedPriority
        self.helpBtnConstraintExpanded.priority = helpBtnConstraintCollapsedPriority
        self.helpBtnConstraintCollapsed.priority = helpBtnConstraintExpandedPriority
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()

            //I need to wait until animate is done so I get right dimension for helpButton's Y.
            if moveTo == UpOrDown.up {
                self.clearViewBehindButtons!.frame = CGRect(x: self.newButton.frame.minX, y: self.helpButton.frame.minY, width: self.newButton.frame.width, height: UIScreen.main.bounds.height - self.helpButton.frame.minY)
            }
            else {
                self.clearViewBehindButtons!.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
            }
        })
    }
    
    func moveButtonsLeftOrRight() {
        
        //I only need to change the new button, since all the other buttons are tethered to it via their constraints and will follow along obligingly.
        let leftSidePriority = self.newButtonXConstraintLeftSide.priority
        let rightSidePriority = self.newButtonXConstraintRightSide.priority
        
        //swap their priorities, which in essence reverses them
        self.newButtonXConstraintLeftSide.priority = rightSidePriority
        self.newButtonXConstraintRightSide.priority = leftSidePriority

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            self.moveLegalLabel()
            self.view.layoutIfNeeded()
        }, completion: { finished in
            self.clearViewBehindButtons!.frame = CGRect(x: self.newButton.frame.minX, y: self.helpButton.frame.minY, width: self.newButton.frame.width, height: UIScreen.main.bounds.height - self.helpButton.frame.minY)
        })
    }

    func moveButtonsOnOrOffscreen() {

        switch self.buttonsOnLeftOrRight {
        case LeftOrRight.left:
            let offscreenPriority = self.newButtonXConstraintLeftSideOffscreen.priority
            let onscreenPriority = self.newButtonXConstraintLeftSide.priority
            //swap them.
            self.newButtonXConstraintLeftSideOffscreen.priority = onscreenPriority
            self.newButtonXConstraintLeftSide.priority = offscreenPriority
        case LeftOrRight.right:
            let offscreenPriority = self.newButtonXConstraintRightSideOffscreen.priority
            let onscreenPriority = self.newButtonXConstraintRightSide.priority
            //swap them.
            self.newButtonXConstraintRightSideOffscreen.priority = onscreenPriority
            self.newButtonXConstraintRightSide.priority = offscreenPriority
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        }, completion: { finished in
            self.clearViewBehindButtons!.frame = CGRect(x: self.newButton.frame.minX, y: self.helpButton.frame.minY, width: self.newButton.frame.width, height: UIScreen.main.bounds.height - self.helpButton.frame.minY)
        })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func checkIfLocatServicesEnabled() -> Promise<LocationServicesStatusResult> {
        
        return Promise {resolve, reject in
            //check if location services enabled
            //info here: https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CLLocationManager_Class/
            
            //for some reason I have to call this on "CLLocationManager"; I can't call it on self.locationManager even though that is pointing to an instance of CLLocationManager.
            let authStatus = CLLocationManager.authorizationStatus()
            
            switch authStatus {
            case .restricted, .denied:
                let errPacket = LocationErrorPacket(locationErrorType: LocationErrorType.userMustEnableLocation, errmsg: "")
                reject(errPacket)
            case .notDetermined:
                resolve(LocationServicesStatusResult.needToAskForPermission)
            case .authorizedAlways, .authorizedWhenInUse:
                resolve(LocationServicesStatusResult.enabled)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        
        //this delegate method gets called on add startup, I noticed (ie, not by me). This prevents a bug where it starts doing stuff for my app when I didn't initiate anything
        if self.promiseForLocationRequest == nil {
            return
        }
        
        if status == CLAuthorizationStatus.denied {
            
            let errPacket = LocationErrorPacket(locationErrorType: LocationErrorType.userMustEnableLocation, errmsg: "")

            self.promiseForLocationRequest?.reject(errPacket)
            return
        }
        
        if status == CLAuthorizationStatus.authorizedAlways || status == CLAuthorizationStatus.authorizedWhenInUse {
            
            //turn off my location if the setting has it off. I noticed that it automatically turns this on if you say allow app to use my location.
            if SqlTalker.getSetting(setting: "showLocationOnMap") != "yes" {
                self.myMapView.showsUserLocation = false
            }
            
            //they allowed access, so get my location. Once it is found, the delegate method "didUpdateLocations" will be called, which is where I resolve the promise
            GlobalFuncs.showHudHourglass(msg: "")
            
            //see https://developer.apple.com/documentation/corelocation/getting_the_user_s_location/using_the_standard_location_service
            //supposedly these help with battery consumption
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10.0  // In meters.
            locationManager.pausesLocationUpdatesAutomatically = true
            
            self.locationManager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        //the array will always have at least one location, acc to docs.
        //the last one is the most recent one.
        if let lastLoc = locations.last {
            self.lastUpdatedLocation = lastLoc
        }
        
        //this delegate method "didupdatelocations" will run on first open, but it's okay b/c the promise var will be null,
        //so this code won't run anything.
        self.promiseForLocationRequest?.fulfill("")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let errPacket = LocationErrorPacket(locationErrorType: LocationErrorType.errorFromDelegate, errmsg: "Cannot get your location".jtLocalize())
        self.promiseForLocationRequest?.reject(errPacket)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {

        if annotation is MKUserLocation {
            //return nil so map view draws "blue dot" for standard user location
            return nil
        }
        
        let customPin = annotation as! MKAnnotationWithExtraInfo
        
        var emojiView: MKAnnotationView!
        var pinView: MKPinAnnotationView!
        var returnView: MKAnnotationView? //this has to be declared optional b/c that's what the return type is
        
        var pinStyle = ""
        var reuseId = ""
        
        //if there's a pin that can be reused, this will return it. If it returns nil, then I need to create a new pin.
        
        pinStyle = self.pinsetsArray[customPin.pinsetIndex].pinstyle

        switch pinStyle {
        case "emoji":
            
            let reuseId = "emojipin" //I used to use just one reuseid, but the pins would shift erratically from pin to emoji; they seem to require their own id
            
            
            emojiView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) //this returns an MKAnnotationView
            
            if emojiView == nil {
                emojiView = MKAnnotationView(annotation: customPin, reuseIdentifier: reuseId)
            }
            else {
                
                //reused pin
                emojiView!.annotation = annotation
            }
            
            //add the emoji
            let size = CGSize(width: 20, height: 20)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            UIColor.clear.set()
            let rect = CGRect(origin: CGPoint(), size: size)
            UIRectFill(CGRect(origin: CGPoint(), size: size))
            
            let str = self.pinsetsArray[customPin.pinsetIndex].emojiorcolor
            str.draw(in:rect, withAttributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 15)])
            let img = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            emojiView!.image = img
            
            returnView = emojiView
            
        case "pin":
            
            reuseId = "standardpin" //I used to use just one reuseid, but the pins would shift erratically from pin to emoji; they seem to require their own id
            
            
            pinView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKPinAnnotationView
            
            if pinView == nil {
                pinView = MKPinAnnotationView(annotation: customPin, reuseIdentifier: reuseId)
            }
            else {
                
                //reused pin
                pinView!.annotation = annotation
            }
            
            pinView.pinTintColor = GlobalFuncs.hexStringToUIColor(hexStr: self.pinsetsArray[customPin.pinsetIndex].emojiorcolor)
            
            returnView = pinView
            
            returnView?.canShowCallout = false
            
        default:
            break
        }
        
        return returnView
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        
        //you have to deselect or you won't be able to select the same annotation twice in a row.
        mapView.deselectAnnotation(view.annotation, animated: false)
        
        if view.annotation is MKUserLocation
        {
            // Don't proceed with custom callout for the view location
            return
        }
        
        self.clickedPinAnnotation = view.annotation as? MKAnnotationWithExtraInfo
        
        self.lastPinset = self.pinsetsArray[self.clickedPinAnnotation!.pinsetIndex]
        self.lastPin = self.pinsetsArray[self.clickedPinAnnotation!.pinsetIndex].pinArray.first(where: { $0.pinName == self.clickedPinAnnotation?.pinName} )
        self.slideInCallout!.PinsetNameLabel.text = self.pinsetsArray[self.clickedPinAnnotation!.pinsetIndex].pinsetName
        self.slideInCallout!.PinNameLabel.text = self.clickedPinAnnotation!.pinName
        self.slideInCallout!.PinDescLabel.text = self.clickedPinAnnotation!.pinDesc
        
        if !(self.lastPin!.picFileName.isEmpty) {
            if let img = PicHandler.getImage(filename: self.lastPin!.picFileName) {
                self.slideInCallout!.imgCtl.contentMode = .scaleAspectFit
                self.slideInCallout!.imgCtl.image = img
                self.slideInCallout!.imgCtlHasPic = true
            }
        }
        else {
            let img = UIImage(named: "picPlaceholder")
            self.slideInCallout!.imgCtl.contentMode = .center //this pic is so tiny that it will warp if it's set to aspectfit
            self.slideInCallout!.imgCtl.image = img
            self.slideInCallout!.imgCtlHasPic = false
        }
        
        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveLinear, animations: {
            
            self.slideInCallout!.frame = self.frameCalloutOnscreen!
            
        }, completion: nil)        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        /*
         I call stop for 2 reasons:
         1) no need to waste battery when I'm not on the map
         2) I need didUpdateLocations to be called.
         
         from https://developer.apple.com/documentation/corelocation/cllocationmanager/1423750-startupdatinglocation
         Calling startUpdatingLocation several times in succession does not automatically result in new events being generated. Calling stopUpdatingLocation() in between, however, does cause a new initial event to be sent the next time you call this method.
 */
        self.locationManager.stopUpdatingLocation()
        
        if segue.identifier == "EditPinSegueFromMap" {
            guard let pinVC = segue.destination as? EditPinTableViewController else {
                print("ERROR!")
                return
            }

            pinVC.passedInPinset = self.lastPinset!
            pinVC.passedInPin = self.lastPin!
            
            pinVC.delegate = self
            //you have to change this to "cancel" for each pushed VC; it doesn't change globally.
            //I used to push the next VC modally, so it could have its own nav controller and cancel/save buttons, but that prevents me from popping 2 back
            //using the VC stack (from "Choose Pinset" all the way back to the Map VC).
            let backItem = UIBarButtonItem()
            backItem.title = "Cancel".jtLocalize() //I set it to "Cancel" for the editPin, so I need to make it a regular back button for this.
            navigationItem.backBarButtonItem = backItem
        }
        else if segue.identifier == "ShowLayersSegue" {
            let vc = segue.destination as! LayersViewController
            vc.mapViewController = self
            
            let backItem = UIBarButtonItem()
            backItem.title = " " //I used to put the word cancel but didn't like that here
            navigationItem.backBarButtonItem = backItem
        }
        else if segue.identifier == "ShowSearchSegue" {

            let vc = segue.destination as! SearchViewController
            vc.coordForSearchTopLeft = self.coordForSearchTopLeft
            vc.coordForSearchBottomRight = self.coordForSearchBottomRight
            vc.myParentMap = self.myMapView

            let backItem = UIBarButtonItem()
            backItem.title = " " //I set it to "Cancel" for the editPin, so I need to make it a regular back button for this.
            navigationItem.backBarButtonItem = backItem
        }
        else if segue.identifier == "ShowSettingsSegue" {
            let backItem = UIBarButtonItem()
            backItem.title = " " //I set it to "Cancel" for the editPin, so I need to make it a regular back button for this.
            navigationItem.backBarButtonItem = backItem
        }
    }
    
    func closeCallout() {

                UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveLinear, animations: {
                    
                    self.slideInCallout!.frame = self.frameCalloutOffscreen!
                    
                }, completion: nil)
    }
    
    func editPinClickedInCustomCallout(pinName:String, pinsetName: String) {
        self.performSegue(withIdentifier: "EditPinSegueFromMap", sender: nil)
    }
    
    func closeClickedInCustomCallout() {
        self.closeCallout()
    }
    
    func GoToMapClickedInCustomCallout() {
        
        //from https://stackoverflow.com/questions/28604429/how-to-open-maps-app-programmatically-with-coordinates-in-swift
        
        let latitude: CLLocationDegrees = self.clickedPinAnnotation!.coordinate.latitude
        let longitude: CLLocationDegrees = self.clickedPinAnnotation!.coordinate.longitude
        
        let regionDistance:CLLocationDistance = 10000
        let coordinates = CLLocationCoordinate2DMake(latitude, longitude)
        let regionSpan = MKCoordinateRegion.init(center: coordinates, latitudinalMeters: regionDistance, longitudinalMeters: regionDistance)
        let options = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: regionSpan.center),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: regionSpan.span)
        ]
        let placemark = MKPlacemark(coordinate: coordinates, addressDictionary: nil)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = self.clickedPinAnnotation!.pinName
        mapItem.openInMaps(launchOptions: options)
    }
    
    func tellUserToEnableLocation() {
        
        let alertController = UIAlertController(
            title: "Location Disabled".jtLocalize(),
            message: "Please enable location access".jtLocalize(),
            preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "Cancel".jtLocalize(), style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        let openAction = UIAlertAction(title: "Open Settings".jtLocalize(), style: .default) { (action) in
            if let url = URL(string:UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        alertController.addAction(openAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func showErrorChangingPinName(errMsg: String) {
        self.showThisSlideInMsg(errMsg: errMsg, errMsgIcon: ErrMsgIcon.warningTriangle)
    }
    
    func shouldAddPinToPrevSetOrNewSet() -> PrevSetOrNewSet {
        //this is to check that all the conditions are there for adding to an existing set
        //if not previous set exists, just return immediately
        //also verify that the prev set still exists. If it became an orphan, it will be gone.
        guard let prevSet = self.lastPinset, SqlTalker.checkForExistenceOfPinsetName(nm: prevSet.pinsetName) == true else {
            return PrevSetOrNewSet.newSet
        }
        
        //if the setting is yes, also return.
        if SqlTalker.getSetting(setting: "createNewSetForNewPin") == "yes" {
            return PrevSetOrNewSet.newSet
        }
        
        //If I got this far, ensure that the pinset isn't already saved to the cloud.
        //I'm double checking from the db instead of the local one b/c they may have added the pinset to the cloud.
        let setToCk = SqlTalker.getLocalPinsetsSingleOrArray(singleOrArray: SingleOrArray.single, pinsetname: prevSet.pinsetName)[0]
        if !(setToCk.cloudid.isEmpty) {
            //this is a special case. I show a msg that I couldn't save to prev set b/c it's in cloud
            return PrevSetOrNewSet.shouldBePrevSetButItsInCloud
        }
        
        //If I got this far, then they can add to the previous set.
        return PrevSetOrNewSet.prevSet
    }
    
    func addPinToPrevSet(passedInCoord: CLLocationCoordinate2D) {
        
          guard let prevPinset = self.lastPinset else {
            self.showThisSlideInMsg(errMsg: "Problem finding last pinset".jtLocalize(), errMsgIcon: ErrMsgIcon.warningTriangle)
            return
        }

          if SqlTalker.doesLatLongAlreadyExist(lat: String(passedInCoord.latitude), lng: String(passedInCoord.longitude), pinsetName: prevPinset.pinsetName) {
            self.showThisSlideInMsg(errMsg: "Pin already exists at that location".jtLocalize(), errMsgIcon: ErrMsgIcon.warningTriangle)
            return
        }
        
        //I'm safe to add it.        
        let addResult = SqlTalker.addPinToDb(pinCoordinate: passedInCoord, createNewPinset: false, lastPinsetName: prevPinset.pinsetName)
        self.lastPin = SqlTalker.getPin(pinsetName: addResult.parentPinsetName, pinName: addResult.pinName!)

        //update that pinset to be shown, in case it was hiding when they added the pin to it.
        SqlTalker.updatePinsetShowHide(pinsetName: prevPinset.pinsetName, isShowing: "y", localOrWeb: LocalOrWeb.local, cloudid: "")

        self.setNextOrPrevSetLabel()
        
        //rechart to show this new pin
        self.chartAllMapPins()
        
        self.myMapView.centerCoordinate = passedInCoord
    }
    
    func setNextOrPrevSetLabel() {
        //if the setting is yes, also return.
        
        let ck = SqlTalker.getSetting(setting: "createNewSetForNewPin")

        let str1 = "Next pin goes to".jtLocalize()
        let str2 = "new set".jtLocalize()
        
        if let pinset = self.lastPinset, ck == "no" {
            self.nextPinsetLabel.text = "\(str1): \(pinset.pinsetName)"
        } else {
            self.nextPinsetLabel.text = "\(str1): <" + str2 + ">"
        }
    }
    
    func updatePin(updatedPin: SinglePin, updatedPinset: SinglePinset) {
        
        let resultPacket = GlobalFuncs.updatePin(updatedPin: updatedPin, updatedPinset: updatedPinset, oldPinName: self.lastPin!.pinName, oldPinsetName: self.lastPinset!.pinsetName)
        
        self.showThisSlideInMsg(errMsg: resultPacket.msg, errMsgIcon: resultPacket.icon)
        
        if let newPin = resultPacket.updatedPin {
            self.lastPin = newPin
        }
        
        self.chartAllMapPins()
    }
    
    func addPinToNewSet(passedInCoord: CLLocationCoordinate2D) {

        let addResult = SqlTalker.addPinToDb(pinCoordinate: passedInCoord, createNewPinset: true, lastPinsetName: "")
        self.lastPinset = SqlTalker.getLocalPinsetsSingleOrArray(singleOrArray: SingleOrArray.single, pinsetname: addResult.parentPinsetName)[0]
        self.lastPin = SqlTalker.getPin(pinsetName: addResult.parentPinsetName, pinName: addResult.pinName!)

        self.setNextOrPrevSetLabel()

        //rechart to show this new pin
        self.chartAllMapPins()
        
        self.myMapView.centerCoordinate = passedInCoord
    }
    
    func pinDeletedInEditPinVC() {
        self.showThisSlideInMsg(errMsg: "Pin deleted".jtLocalize(), errMsgIcon: ErrMsgIcon.successfulCheckmark)
    }
    
    func showHideButtons(areHidden: Bool) {
        self.newButton.isHidden = areHidden
        self.mySearchButton.isHidden = areHidden
        self.myLayersButton.isHidden = areHidden
        self.gpsLocateButton.isHidden = areHidden
        self.settingsButton.isHidden = areHidden
        self.helpButton.isHidden = areHidden
    }
    
    func startSearchWithinCoordinates(topLeft: CGPoint, bottomRight: CGPoint) {        
        self.removePolygonOverlay()
        
        self.coordForSearchTopLeft = self.myMapView.convert(topLeft, toCoordinateFrom: self.myMapView)
        self.coordForSearchBottomRight = self.myMapView.convert(bottomRight, toCoordinateFrom: self.myMapView)
        
        self.performSegue(withIdentifier: "ShowSearchSegue", sender: nil) //coords are passed in "prepare(for segue..."
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        
        let overlayPolygonRenderer = MKPolygonRenderer(overlay: overlay)
        overlayPolygonRenderer.fillColor = UIColor.cyan.withAlphaComponent(0.2)
        overlayPolygonRenderer.strokeColor = UIColor.blue.withAlphaComponent(0.7)
        overlayPolygonRenderer.lineWidth = 3
        
        return overlayPolygonRenderer
    }
    
    func removePolygonOverlay () {
        
        //this gets called when you click the OK button, whereas "closePolygonOverlay" gets called when you hit Cancel.
        
        if let drawingCanvas = self.myRectangleSearchOverlay {
            drawingCanvas.removeFromSuperview()
        }
        
        //need to change this so I have a reference to the overlay.
        let overlays = self.myMapView.overlays
        self.myMapView.removeOverlays(overlays)
       
        self.moveButtonsOnOrOffscreen()
        self.nextPinsetLabelContainerView.isHidden = false
    }
    
    func showPhotoModal() {
        
        self.addPhotoView?.pinName.text = self.lastPin?.pinName
        self.addPhotoView?.pinsetName.text = self.lastPinset?.pinsetName
        self.addPhotoView?.progressBar.progress = 1.0
        self.view.addSubview(self.modalCurtain!)
        
        //have to do this or the modal will be on the top, b/c it is the most recent to be added to the view hierarchy
        self.view.bringSubviewToFront(self.addPhotoView!)
        
        //in case it was still running
        self.addPhotoTimer?.invalidate()

        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveEaseOut, animations: {
            self.addPhotoView!.frame = self.addPhotoView!.onscreenFrame!
            },
           completion: { (value:Bool) in
                    self.addPhotoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (time) in
                        
                        if self.addPhotoView?.progressBar.progress == 0.0 {
                            self.addPhotoTimer?.invalidate()
                            self.closePhotoModal()
                            return
                        }
                        
                        self.addPhotoView?.progressBar.progress -= 0.25
                    })
            }
        )
    }
    
    func deleteClickedInPhotoModal() {
        self.addPhotoTimer?.invalidate()
        self.modalCurtain?.removeFromSuperview()
        self.addPhotoView?.frame = self.addPhotoView!.offscreenFrame!
        
        guard let prevPin = self.lastPin?.pinName else {return}
        guard let prevPinset = self.lastPinset else {return}
        
        let refreshAlert = UIAlertController(title: "Verify delete".jtLocalize(), message: "Are you sure you want to delete this pin".jtLocalize(), preferredStyle: UIAlertController.Style.actionSheet)
        
        refreshAlert.addAction(UIAlertAction(title: "Delete".jtLocalize(), style: .destructive, handler: { (action: UIAlertAction!) in
            //they selected to delete it.
            SqlTalker.deletePin(pinName: prevPin, pinsetName: prevPinset.pinsetName)
            
            //delete orphans. No need to tell them; just assume an new pinset will be removed.
            _ = SqlTalker.deleteOrphanPinsets()
            
            self.lastPin = nil
            
            self.chartAllMapPins()
            
            self.showThisSlideInMsg(errMsg: "Pin deleted".jtLocalize(), errMsgIcon: ErrMsgIcon.successfulCheckmark)
        }))
        
        refreshAlert.addAction(UIAlertAction(title: "Cancel".jtLocalize(), style: .cancel, handler: { (action: UIAlertAction!) in
            refreshAlert.dismiss(animated: true, completion: nil)
        }))
        
        present(refreshAlert, animated: true, completion: nil)
    }
    
    func editClickedInPhotoModal() {
        self.addPhotoTimer?.invalidate()
        self.modalCurtain?.removeFromSuperview()
        self.addPhotoView?.frame = self.addPhotoView!.offscreenFrame!
        performSegue(withIdentifier: "EditPinSegueFromMap", sender: self)
    }
    
    func closeClickedInPhotoModal() {
        self.addPhotoTimer?.invalidate()
        self.closePhotoModal()
    }
    
    func cameraClickedInPhotoModal() {
        self.addPhotoTimer?.invalidate()
        self.closePhotoModal()

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            self.showImgPicker(typ: UIImagePickerController.SourceType.camera)
            
            //after you pick an img, it calls "didFinishPickingMediaWithInfo"
        }
        else {
            self.showMsgbox(title: "Error".jtLocalize(), msg: "Camera not available".jtLocalize())
        }
    }
    
    func photoRollClickedInPhotoModal() {
        self.addPhotoTimer?.invalidate()
        self.closePhotoModal()

        self.showImgPicker(typ: UIImagePickerController.SourceType.photoLibrary)
        
        //after you pick an img, it calls "didFinishPickingMediaWithInfo"
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    func showImgPicker(typ:UIImagePickerController.SourceType) {
        self.imagePicker.sourceType = typ
        
        present(self.imagePicker, animated: true, completion: {
            self.imagePicker.navigationBar.topItem?.rightBarButtonItem?.isEnabled = true
        })
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {

        picker.dismiss(animated: true, completion: nil)
        
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            return
        }
        
        guard let imageSmaller = PicHandler.resizeImage(image: image, newWidth: 600.0) else {
            return
        }
        
        //do full jpg compression on it
        guard let jpg = imageSmaller.jpegData(compressionQuality: 0.3) else {
            self.showMsgbox(title: "Error".jtLocalize(), msg: "Error getting pic".jtLocalize())
            return
        }
        
        if let picname = PicHandler.saveJpgToFile(jpg: jpg) {
            let sql = "update pins set picfilename = ? where pinsetname=? and pinname=?"
            SqlTalker.runSql_NoReturnRecs(rawSql: sql, args: [picname, self.lastPinset!.pinsetName, self.lastPin!.pinName])
            
            self.lastPin!.picFileName = picname
        }
        
        //rechart to include this new pin's image
        self.chartAllMapPins()
        
        //go to the edit screen for this pin
        performSegue(withIdentifier: "EditPinSegueFromMap", sender: self)
    }
    
    func closePhotoModal() {
        UIView.animate(withDuration: 0.3, delay: 0.0, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.addPhotoView!.frame = self.addPhotoView!.offscreenFrame!
        },
               completion: { (value:Bool) in
                self.modalCurtain?.removeFromSuperview()
               }
        )
    }
    
    func pinsetNameChanged(oldPinsetName: String, newPinsetName: String) {
        //this gets called from ViewPinsetVC if they changed a pinset's name.
        if self.lastPinset?.pinsetName == oldPinsetName {
            self.lastPinset?.pinsetName = newPinsetName
            self.setNextOrPrevSetLabel()
        }
    }

    func copyOrMovePinToDifferentPinset(changedToPinsetName: String, pinAction: PinAction) {
        
        let resultPacket = GlobalFuncs.copyOrMovePinToDifferentPinset(oldPin: self.lastPin!, oldPinset: self.lastPinset!, changedToPinsetName: changedToPinsetName, pinAction: pinAction)
            self.showThisSlideInMsg(errMsg: resultPacket.msg, errMsgIcon: resultPacket.icon)
        
        self.chartAllMapPins()
    }
    
    func copyOrMovePinToNewPinset(newPinsetName: String, newPinsetDesc: String, pinAction: PinAction) {

        let resultPacket = GlobalFuncs.copyOrMovePinToNewPinset(oldPin: self.lastPin!, oldPinset: self.lastPinset!, newPinsetName: newPinsetName, newPinsetDesc: newPinsetDesc, pinAction: pinAction)
        self.showThisSlideInMsg(errMsg: resultPacket.msg, errMsgIcon: resultPacket.icon)
        
        self.chartAllMapPins()
    }

    public func createCurtainForOnboarding() -> UIView {
        
        let scrht:CGFloat = UIScreen.main.bounds.height
        let scrwd:CGFloat = UIScreen.main.bounds.width
        
        let curtainForOnboarding = UIView(frame: CGRect(x: 0,y: 0, width: scrwd, height: scrht))
        curtainForOnboarding.backgroundColor = UIColor.black
        curtainForOnboarding.alpha = 0.5
        
        return curtainForOnboarding
    }

    func openOnboardingView() {
        //set it back to 0 in case they already showed it and left it scrolled to the right
        self.onboardingView.currentPage = 0
        self.onboardingView.scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        
        self.view.addSubview(self.curtainForOnboarding)
        self.view.addSubview(self.onboardingView)
        
        self.onboardingView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 1, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [], animations: {
            self.onboardingView.transform = CGAffineTransform(scaleX: 1, y: 1)
        }, completion: nil)
    }
    
    func closeOnboardingView() {
        
        UIView.animate(withDuration: 0.2, delay: 0.0, options: UIView.AnimationOptions.curveEaseOut, animations: {
            self.onboardingView.alpha = 0.0
        }, completion: {
            (finished: Bool) -> Void in
            // On main thread
            DispatchQueue.main.async {
                () -> Void in
                self.onboardingView.removeFromSuperview()
                self.curtainForOnboarding.removeFromSuperview()
                
                //puts its alpha back to 1 in case they show it again
                self.onboardingView.alpha = 1
                
                if self.pinsetsArray.count == 0 {
                    self.findMeOnMap(promptUserIfSettingDisabled: false, doZoomOutZoomInBeforeFinding: true)
                }
            }
        })
    }
    
    public func createOnboardingView(delegate:OnboardingViewDelegate) -> OnboardingView {
        
        let scrht:CGFloat = UIScreen.main.bounds.height
        let scrwd:CGFloat = UIScreen.main.bounds.width
        
        let onboardingView = Bundle.main.loadNibNamed("OnboardingView", owner: self, options: nil)?.first as! OnboardingView
        
        onboardingView.delegate = delegate
        
        let x:CGFloat = scrwd * 0.1
        let y:CGFloat = scrht * 0.1
        
        let wd:CGFloat = scrwd - (x * 2)
        let ht:CGFloat = scrht - (y * 2)
        
        onboardingView.frame = CGRect(x: x, y: y, width: wd, height: ht)
        
        var namesDescs:[OnboardingNameDesc] = []
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle1".jtLocalize(),
            desc: "OnboardingText1".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle2".jtLocalize(),
            desc: "OnboardingText2".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle3".jtLocalize(),
            desc: "OnboardingText3".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle4".jtLocalize(),
            desc: "OnboardingText4".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle5".jtLocalize(),
            desc: "OnboardingText5".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle6".jtLocalize(),
            desc: "OnboardingText6".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle7".jtLocalize(),
            desc: "OnboardingText7".jtLocalize()
        ))
        
        namesDescs.append(OnboardingNameDesc(
            nm: "OnboardingTitle8".jtLocalize(),
            desc: "OnboardingText8".jtLocalize()
        ))

        var pages:[UIView] = []
        
        for i in 0..<namesDescs.count {
            let pg:OnboardingPage = Bundle.main.loadNibNamed("OnboardingPage", owner: self, options: nil)?.first as! OnboardingPage
            pg.titleLabel.text = namesDescs[i].nm
            pg.descLabel.text = namesDescs[i].desc
            pages.append(pg)
        }
        
        onboardingView.numPages = pages.count
        
        //there's a problem here. The constraints haven't kicked in yet since this
        //view hasn't been added, but I need to know the height of the scrollview.
        //I'm pretty sure the gap at the bottom is 42.
        let bottomGap:CGFloat = 42
        
        let pageHeight = ht - bottomGap
        
        onboardingView.scrollView.contentSize = CGSize(width: wd * CGFloat(pages.count), height: pageHeight)
        
        for i in 0 ..< pages.count {
            pages[i].translatesAutoresizingMaskIntoConstraints = false
            onboardingView.scrollView.addSubview(pages[i])
            
            pages[i].widthAnchor.constraint(equalToConstant: wd).isActive = true
            pages[i].heightAnchor.constraint(equalToConstant: pageHeight).isActive = true
            pages[i].topAnchor.constraint(equalTo: onboardingView.scrollView.topAnchor, constant: 0).isActive = true
            
            if i == 0 {
                pages[i].leadingAnchor.constraint(equalTo: onboardingView.scrollView.leadingAnchor, constant: 0).isActive = true
            } else {
                pages[i].leadingAnchor.constraint(equalTo: pages[i-1].trailingAnchor, constant: 0).isActive = true
            }
        }
        
        return onboardingView
    }
    
    public func addPinAtCoordinate(loc:CLLocationCoordinate2D) -> Promise<String> {
        
        return Promise {resolve, reject in
            //it's enabled, so put a pin there.
            switch self.shouldAddPinToPrevSetOrNewSet() {
            case PrevSetOrNewSet.newSet:
                self.addPinToNewSet(passedInCoord: loc)
            case PrevSetOrNewSet.prevSet:
                self.addPinToPrevSet(passedInCoord: loc)
            case PrevSetOrNewSet.shouldBePrevSetButItsInCloud:
                self.addPinToNewSet(passedInCoord: loc)
            }
            
            resolve("")
        }
    }
    
    func initiateLocationRequest(resultOfCheck: LocationServicesStatusResult) ->Promise<String> {
                
        //since both of these actions call a delegate method, I'm stashing a promise in a class variable
        //so I can resolve/reject it from the delegate method.
        self.promiseForLocationRequest = Promise<String>()
        
        //now start the correct process.
        switch resultOfCheck {
        case .enabled:
            self.locationManager.stopUpdatingLocation() //I stop it then start it to force it to re-call didupdateLocation
            self.locationManager.startUpdatingLocation()

        case .needToAskForPermission:
            //need to hide the hourglass so they can answer the request message.
            GlobalFuncs.hideHudHourglass(funcToRunAfterHiding: {
                 //callback "didChangeAuthorization" called after they respond (will then call "didUpdateLocations" if they say yes)
                //findMeOnMap is where the the next ".then" will run when this is fulfilled in the delegate method "didUpdateLocations"
                self.locationManager.requestWhenInUseAuthorization()
            })
        }
        
        return self.promiseForLocationRequest! //***I PASS BACK A BLANK PROMISE INTENTIONALLY, SO I CAN RESOLVE/REJECT FROM the delegate methods didChangeAuthorization etc.
    }
    
    func getMapLinkClickedInCustomCallout() {
        
        guard let lat = self.lastPin?.lat, let lng = self.lastPin?.lng else {
            return
        }
        let url = "https://www.sharetheres.com/pinLocator.html?lat=\(lat)&lng=\(lng)"
        
        let alertController: UIAlertController = UIAlertController(title: "Copy this hyperlink".jtLocalize(), message: url, preferredStyle: .alert)
        
        let cancelAction: UIAlertAction = UIAlertAction(title: "Done".jtLocalize(), style: .default) { action -> Void in
        }
        alertController.addAction(cancelAction)
        
        let copyAction: UIAlertAction = UIAlertAction(title: "Copy".jtLocalize(), style: .cancel) { action -> Void in
            UIPasteboard.general.string = url
        }
        alertController.addAction(copyAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    func locationError(locationErrorPacketAsError: Error) -> Void {
        guard let locationErrorPacket = locationErrorPacketAsError as? LocationErrorPacket else {
            self.showMsgbox(title: "Problem".jtLocalize(), msg: "Weird error".jtLocalize())
            return
        }
        
        switch locationErrorPacket.locationErrorType {
            
        case .userMustEnableLocation:
            self.tellUserToEnableLocation()
            
        case .errorFromDelegate:
            let alertController = UIAlertController(title: "Error".jtLocalize(),
                                                    message: locationErrorPacket.errmsg,
                                                    preferredStyle: UIAlertController.Style.alert)
            
            alertController.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default,handler: nil))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
}
