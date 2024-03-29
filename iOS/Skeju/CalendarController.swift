//
//  CalendarController.swift
//  Skeju
//
//  Created by Sung Kim on 3/6/16.
//  Copyright © 2016 GeorgiaTech. All rights reserved.
//

import Foundation
import UIKit
import JTCalendar
import CalendarLib
import EventKit
import EventKitUI

class CalendarController: UIViewController, JTCalendarDelegate {
    @IBOutlet var statusBarView: UIView!
    @IBOutlet var calendarMenuView: JTCalendarMenuView!
    @IBOutlet var calendarContentView: JTHorizontalCalendarView!
    @IBOutlet var dayPlannerContainer: UIView!
    
    let screenWidth = UIScreen.mainScreen().bounds.width
    let screenHeight = UIScreen.mainScreen().bounds.height
    let userDefaults = NSUserDefaults()

    var dayPlannerController: DayPlannerController!
    var calendarManager: JTCalendarManager!
    var _dateSelected: NSDate?
    var _eventStore: EKEventStore?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        calendarManager = JTCalendarManager()
        calendarManager.delegate = self
        initUI()
        _eventStore = EKEventStore()

        calendarManager.menuView = calendarMenuView
        calendarManager.contentView = calendarContentView
        calendarManager.setDate(NSDate())
        
        dayPlannerController = DayPlannerController(eventStore: _eventStore)
        dayPlannerController.calendar = NSCalendar.currentCalendar()
        
        self.addChildViewController(dayPlannerController)
        self.dayPlannerContainer.addSubview(dayPlannerController.view)
        dayPlannerController.view.frame = self.dayPlannerContainer.bounds
        dayPlannerController.didMoveToParentViewController(self)
        
        loadEventStoreToDB(_eventStore!)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        calendarManager.reload()
    }
    
    func calendar(calendar: JTCalendarManager!, prepareDayView day: UIView!) {
        if let dayView = day as? JTCalendarDayView {
            dayView.hidden = false
            dayView.textLabel.font = UIFont.boldSystemFontOfSize(15)
            if dayView.isFromAnotherMonth {
                dayView.textLabel.textColor = UIColor.lightGrayColor()
                dayView.textLabel.font = UIFont.systemFontOfSize(12)
                dayView.textLabel.alpha = 0.5
            } else if calendarManager.dateHelper.date(NSDate(), isTheSameDayThan: dayView.date) {
                dayView.circleView.hidden = false
                dayView.circleView.backgroundColor = UIColor(red: 96/255.0, green: 170/255.0, blue: 1, alpha: 1)
                dayView.dotView.backgroundColor = UIColor.whiteColor()
                dayView.textLabel.textColor = UIColor.whiteColor()
            } else if _dateSelected != nil && calendarManager.dateHelper.date(_dateSelected, isTheSameDayThan: dayView.date) {
                dayView.circleView.hidden = false
                dayView.circleView.backgroundColor = UIColor(red: 187/255.0, green: 88/255.0, blue: 88/255.0, alpha: 1)
                dayView.dotView.backgroundColor = UIColor.whiteColor()
                dayView.textLabel.textColor = UIColor.whiteColor()
            } else {
                dayView.circleView.hidden = true
                dayView.dotView.backgroundColor = UIColor.redColor()
                dayView.textLabel.textColor = UIColor.blackColor()
            }
            
//            if self.haveEventForDay(dayView.date) {
//                dayView.dotView.hidden = false
//            } else {
//                dayView.dotView.hidden = true
//            }
        }
    }
    
    func calendar(calendar: JTCalendarManager!, didTouchDayView day: UIView!) {
        if let dayView = day as? JTCalendarDayView {
            _dateSelected = dayView.date
            if let dp = self.dayPlannerController {
                dp.dayPlannerView.scrollToDate(dayView.date, options: MGCDayPlannerScrollType.init(rawValue: 1), animated: true)
            }
            dayView.circleView.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.1, 0.1)
            UIView.transitionWithView(dayView, duration: 0.3, options: UIViewAnimationOptions.AllowAnimatedContent, animations: {
                    dayView.circleView.transform = CGAffineTransformIdentity
                    self.calendarManager.reload()
                }, completion: nil)
            
            if !calendarManager.dateHelper.date(calendarContentView.date, isTheSameMonthThan: dayView.date) {
                if self.calendarContentView.date.compare(dayView.date) == NSComparisonResult.OrderedAscending {
                    self.calendarContentView.loadNextPageWithAnimation()
                } else {
                    self.calendarContentView.loadPreviousPageWithAnimation()
                }
            }
        }
    }
    
    func initUI() {
        let views = [statusBarView, calendarMenuView, calendarContentView]
        for view in views {
            view.clipsToBounds = false
            view.layer.masksToBounds = false
            view.layer.shadowColor = UIColor.darkGrayColor().CGColor
            view.layer.shadowRadius = 5
            view.layer.shadowOffset = CGSizeMake(0, 5)
            view.layer.shadowOpacity = 0.75
        }
    }
    
    func loadEventStoreToDB(eventStore: EKEventStore) {
        let userFID = userDefaults.valueForKey("FBID") as! String
        let request = NSMutableURLRequest(URL: NSURL(string: "http://api-skeju.rhcloud.com/event/get/\(userFID)")!)
        request.HTTPMethod = "GET"
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) { data, response, error in
            guard error == nil && data != nil else {                                                          // check for fundamental networking error
                print("error=\(error)")
                return
            }
            
            if let httpStatus = response as? NSHTTPURLResponse where httpStatus.statusCode != 200 {           // check for http errors
                print("statusCode should be 200, but is \(httpStatus.statusCode)")
                print("response = \(response)")
            }
            
            let responseString = NSString(data: data!, encoding: NSUTF8StringEncoding)!
            if responseString == "[]" {
                NSLog("Loading EKEventStore of \(userFID)")
                let calendar = NSCalendar.currentCalendar()
                let oneMonthAgo = calendar.dateByAddingUnit(.Month, value: -1, toDate: NSDate(), options: [])!
                let twoMonthsLater = calendar.dateByAddingUnit(.Month, value: 2, toDate: NSDate(), options: [])!
                
                let predicate = self._eventStore?.predicateForEventsWithStartDate(oneMonthAgo, endDate: twoMonthsLater, calendars: nil)
                self._eventStore?.enumerateEventsMatchingPredicate(predicate!, usingBlock: { (event, stop) in
                    let postReq = NSMutableURLRequest(URL: NSURL(string: "http://api-skeju.rhcloud.com/event")!)
                    postReq.HTTPMethod = "POST"
                    let userId: String = self.userDefaults.valueForKey("FBID") as! String
                    let availability: String = String(event.availability.rawValue)
                    let startDate: String = String(event.startDate)
                    let endDate: String = String(event.endDate)
                    let allDay: String = String(event.allDay)
                    let isDetached: String = String(event.isDetached)
                    let occurrenceDate: String = String(event.occurrenceDate)
                    let status: String = String(event.status.rawValue)
                    let postString = "eventIdentifier=\(event.eventIdentifier)&userId=\(userId)&otherId=nil&availability=\(availability)&startDate=\(startDate)&endDate=\(endDate)&allDay=\(allDay)&isDetached=\(isDetached)&occurenceDate=\(occurrenceDate)&organizer=nil&status=\(status)"
                    postReq.HTTPBody = postString.dataUsingEncoding(NSUTF8StringEncoding)
                    let task = NSURLSession.sharedSession().dataTaskWithRequest(postReq) { data, response, error in
                        guard error == nil && data != nil else {
                            print("error=\(error)")
                            return
                        }
                        
                        if let httpStatus = response as? NSHTTPURLResponse where httpStatus.statusCode != 200 {
                            print("statusCode should be 200, but is \(httpStatus.statusCode)")
                            print("response = \(response!)")
                        }
                    }
                    task.resume()
                })
            }
        }
        task.resume()
    }
    
    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return UIStatusBarStyle.LightContent
    }
}