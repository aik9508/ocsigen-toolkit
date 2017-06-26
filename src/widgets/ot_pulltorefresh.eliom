[%%shared.start]

[%%client
  open Eliom_content.Html
]

open Eliom_content.Html.D

[%%client

  module type PULLTOREFRESH = sig
    val dragThreshold : float 
    val moveCount : int
    val headContainerHeight : int
    val pullDownIcon : Html_types.div  Eliom_content.Html.D.elt
    val loadingIcon : Html_types.div  Eliom_content.Html.D.elt
    val successIcon : Html_types.div  Eliom_content.Html.D.elt
    val failureIcon : Html_types.div  Eliom_content.Html.D.elt
    val pullText :  Html_types.span  Eliom_content.Html.D.elt 
    val container :  Html_types.div  Eliom_content.Html.D.elt
    val pullDownText : string
    val releaseText : string
    val loadingText : string
    val successText : string
    val failureText : string
    val rotateGradually : bool
    val blockPullIcon : bool
    val afterPull : unit -> bool Lwt.t
  end

  module Make(Elt:PULLTOREFRESH) = struct
    let dragThreshold = Elt.dragThreshold 
    let moveCount  = min (max 100 Elt.moveCount) 500
    let dragStart = ref (-1) 
    let percentage = ref 0. 
    let joinRefreshFlag = ref false 
    let refreshFlag = ref false 
    let pullText = To_dom.of_element Elt.pullText 
    let container = Elt.container
    let js_container = To_dom.of_element container

    let show =
      let icon_list = 
        [Elt.pullDownIcon; Elt.loadingIcon; Elt.successIcon; Elt.failureIcon]
      in
      fun elt ->
        List.iter (fun x -> 
          if x == elt 
          then Manip.Class.remove x "ot-display-none" 
          else Manip.Class.add x "ot-display-none") 
          icon_list 

    let touchstart_handler ev _ =
      Dom_html.stopPropagation ev;
      if !refreshFlag || !joinRefreshFlag then Dom.preventDefault ev
      else begin
        let touch = ev##.changedTouches##item(0) in
        Js.Optdef.iter touch (fun touch -> dragStart:= touch##.clientY);
        Manip.Class.remove container "ot-transition-on";
        show Elt.pullDownIcon;
        if  Elt.rotateGradually then
          Manip.Class.remove Elt.pullDownIcon "ot-transition-on"
        else
          Manip.Class.remove Elt.pullDownIcon "ot-up" ;
      end; 
      Lwt.return_unit

    let touchmove_handler_ ev =
      Dom.preventDefault ev;
      let translateY = -. !percentage *. (float_of_int moveCount)  in
      joinRefreshFlag := true;
      if Elt.rotateGradually 
      then begin
        let rotate_deg = 
          int_of_float (-180. *. !percentage /. dragThreshold) in
        let rotate_deg = 
          if Elt.blockPullIcon 
          then min 180 rotate_deg 
          else min 360 (2*rotate_deg) in
        (To_dom.of_element Elt.pullDownIcon)##.style##.transform := 
          Js.string ("rotate("^ (string_of_int rotate_deg) ^"deg)")
      end;
      if  -. !percentage > dragThreshold 
      then begin
        pullText##.textContent := Js.some (Js.string Elt.releaseText);
        if not Elt.rotateGradually 
        then Manip.Class.add Elt.pullDownIcon "ot-up"
      end
      else begin
        pullText##.textContent := Js.some (Js.string Elt.pullDownText);
        if not Elt.rotateGradually 
        then Manip.Class.remove Elt.pullDownIcon "ot-up"
      end;
      js_container##.style##.transform := 
        Js.string ("translate3d(0," ^ (string_of_float translateY) ^ "px,0)")

    let touchmove_handler ev _ =
      Dom_html.stopPropagation ev;
      if !dragStart >= 0 
      then begin
        if !refreshFlag 
        then Dom.preventDefault ev
        else if ev##.touches##.length=1 
        then begin
          let target = ev##.changedTouches##item(0) in
          Js.Optdef.iter target (fun target ->
            percentage := 
              (float_of_int (!dragStart - target##.clientY))/.
              (float_of_int Dom_html.window##.screen##.height) 
          );
          (*move the container if and only if scrollTop = 0 and 
            the page is scrolled down*)
          if Dom_html.document##.body##.scrollTop = 0 && !percentage<0. 
          then touchmove_handler_ ev 
          else joinRefreshFlag:=false
        end
      end;
      Lwt.return_unit

    let refresh () =
      Manip.Class.add container "ot-transition-on";
      pullText##.textContent := Js.some ( Js.string Elt.loadingText);
      show Elt.loadingIcon;
      js_container##.style##.transform := 
        Js.string ("translate3d(0," ^ 
                   (string_of_int Elt.headContainerHeight) ^ 
                   "px,0)");
      refreshFlag := true;
      Lwt.async ( 
        fun () ->
          let%lwt b = Elt.afterPull () in 
          if b then (*if page refresh succeeds*)
            ignore( 
              Dom_html.window##setTimeout (
                Js.wrap_callback (
                  fun () -> 
                    pullText##.textContent := 
                      Js.some (Js.string Elt.successText);
                    show Elt.successIcon;
                    js_container##.style##.transform := 
                      Js.string ("translate3d(0,0,0)");
                    refreshFlag:=false)) 700.) 
            (*if the page refreshing is finished instantaneously,
              setTimeout is used to show the animation*)
          else
            begin (*if page refresh fails*)
              pullText##.textContent := Js.some (Js.string Elt.failureText) ;
              show Elt.failureIcon;
              js_container##.style##.transform := 
                Js.string ("translate3d(0,0,0)");
              ignore (
                Dom_html.window##setTimeout 
                  (Js.wrap_callback (fun () -> refreshFlag := false))  500.)
            end;
          Lwt.return_unit )

    let scroll_back () = 
      (*scroll back to top if |percentage| < dragThreshold*)
      if !joinRefreshFlag 
      then begin
        Manip.Class.add container "ot-transition-on";
        Manip.Class.add Elt.pullDownIcon "ot-transition-on";
        (To_dom.of_element Elt.pullDownIcon)##.style##.transform := 
          Js.string ("rotate(0deg)") ;
        js_container##.style##.transform := 
          Js.string ("translate3d(0,0,0)");
        ignore (
          Dom_html.window##setTimeout 
            (Js.wrap_callback (fun () -> refreshFlag := false))  500.)
      end

    let touchend_handler ev _ =
      if !percentage<0. && !dragStart >= 0 
      then if !refreshFlag 
        then Dom.preventDefault ev 
        else begin
          if -. !percentage > dragThreshold && !joinRefreshFlag 
          then refresh ()
          else scroll_back ();
          (*reinitialize paramaters*)
          joinRefreshFlag := false;
          dragStart := -1;
          percentage := 0.
        end;
      Lwt.return_unit

    let init () =
      let open Lwt_js_events in 
      Lwt.async (fun () -> touchstarts js_container touchstart_handler);
      Lwt.async (fun () -> touchmoves js_container touchmove_handler);
      Lwt.async (fun () -> touchends js_container touchend_handler);
      Lwt.async (fun () -> touchcancels js_container touchend_handler);
  end
]

let make 
    ?(dragThreshold = 0.3) 
    ?(moveCount = 200)  
    ?(pullDownIcon= div ~a:[a_class ["ot-default-arrow-icon"]] []) 
    ?(loadingIcon = div ~a:[a_class ["ot-default-spinner"]] [])
    ?(successIcon =  div ~a:[a_class ["ot-default-icon-success"]] [])
    ?(failureIcon = div ~a:[a_class ["ot-default-icon-failure"]] [])
    ?(pullText = span [])
    ?(headContainer = div ~a:[a_class ["ot-default-head-container"]] [])
    ?(successText = "The page is refreshed")
    ?(failureText = "An error has occured")
    ?(pullDownText = "Pull down to refresh...")
    ?(releaseText = "Release to refresh...")
    ?(loadingText = "Loading...")
    ?(rotateGradually = false) 
    ?(blockPullIcon = true) 
    ?(alreadyAdded = false)
    ~content 
    (afterPull: (unit-> bool Lwt.t) Eliom_client_value.t) =
  let container = div [ headContainer; content ] in
  ignore (
    [%client 
      (
        Manip.Class.add ~%pullDownIcon "ot-arrow-icon";
        Manip.Class.add ~%headContainer "ot-head-container";
        if not ~%rotateGradually 
        then Manip.Class.add ~%pullDownIcon "ot-transition-on";
        if not ~%alreadyAdded 
        then begin
          let icon_list = 
            [~%pullDownIcon;~%loadingIcon;~%successIcon;~%failureIcon] in
          List.iter 
            (fun elt -> Manip.Class.add elt "ot-display-none") 
            icon_list;
          Manip.appendChildren ~%headContainer icon_list;
          Manip.appendChild ~%headContainer ~%pullText;
        end;
        let onload = fun () ->
          let module Ptr_elt = 
          struct
            let dragThreshold = ~%dragThreshold
            let moveCount = ~%moveCount
            let headContainerHeight = 
              (To_dom.of_element ~%headContainer)##.scrollHeight
            let pullDownIcon = ~%pullDownIcon
            let loadingIcon = ~%loadingIcon
            let successIcon = ~%successIcon
            let failureIcon = ~%failureIcon
            let pullText = ~%pullText
            let container = ~%container
            let pullDownText = ~%pullDownText
            let releaseText = ~%releaseText
            let loadingText = ~%loadingText
            let successText = ~%successText
            let failureText = ~%failureText
            let rotateGradually = ~%rotateGradually
            let blockPullIcon = ~%blockPullIcon
            let afterPull = ~%afterPull
          end in 
          let module Ptr = Make(Ptr_elt) in
          Ptr.init();
        in
        Eliom_client.onload onload  : unit )
    ]);
  Eliom_content.Html.F.
    (div ~a:[a_class ["ot-pull-to-refresh-wrapper"]][container])
