class OwniStory
  constructor: (data) ->
    @data = data

    # Define static graph settings
    @graphSettings =
      width : $(document).width() * 0.96
      height : $(document).height() * 0.96
      padding : 30
      layoutGravity : -0.01
      damper : 0.07
      animationSpeed : 1000
      groupIdentifier : 'job'

    # Define dynamic graph settings
    @graphSettings["circleCenter"] =
        x : @graphSettings.width / 2
        y : @graphSettings.height / 2
    @graphSettings["circleRadius"] = (@graphSettings.height / 3)

    # Define instance variables
    # SVG visualization
    @vis = null
    # List of all nodes from csv files
    @prenodes = []
    # List of nodes already added to the visualization
    @nodes = []
    # Force layout
    @force = null
    # List of all the circles in the visualization
    @circles = null
    # List of all the labels
    @labels = null
    # Time before next timeout in ms
    @nextTimeout = @graphSettings.animationSpeed
    # List of employee changes
    @employeeChanges = []
    # List of group of employee (grouped by job function)
    @groups = null
    # Function to define the color of each group
    @fillGroupColor = null
    # List of center (x,y) for every enterprises
    @enterpriseCenters = null
    # Current date on the timeline event
    @currentDate = moment("2008-03-01")
    # Set total months between the beginning and now
    @total_months = moment().diff(@currentDate, 'months')
    @pastMonths = 0
    # Store the timeline
    @timeline = null
    # List to the tooltip
    @tooltip = new CustomTooltip("tooltip")

    # Initialize the force layout
    this.start()
    # Compute data to define all nodes
    this.createPrenodes()
    # Define groups of employee
    this.createGroup(@graphSettings.groupIdentifier)
    # Compute enterprises data to define a center for each of them
    this.createEnterprises()
    # Create the visualization
    this.createVis()


    # Launch the first animation
    @timer = setTimeout =>
      this.animate()
    , @nextTimeout



  # Define the force layout
  start: () =>
    @force = d3.layout.force()
      .nodes(@nodes)
      .size([@graphSettings.width, @graphSettings.height])

    @force.gravity(@graphSettings.layoutGravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        # On every tick, every circle are moved to their appropriate center
        @vis.selectAll("circle").each(this.moveTowardsCenter(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)

  # Read data from the cvs and create a new node for every line
  createPrenodes: () =>
    @prenodes = []

    @data.forEach (d) =>
      node =
        id: d.id
        radius: 15
        x: Math.random() * @graphSettings.width
        y: Math.random() * @graphSettings.height
        job: d.job
        name: d.name
        twitterAccount: d.twitter_account
        currentEnterprise : "Owni"
        futurEnterprise: d.enterprise
        hiringDate : moment(d.hiring_date)
        leavingDate : moment(d.leaving_date)
        added: false

      @prenodes.push node

    # Sort data by hiring date
    @prenodes.sort (a,b) -> a.hiringDate - b.hiringDate


  # Get every employee job function to create a list.
  # This list will be used to fill a different color depending the job function
  createGroup: (groupIdentifier) =>
    # Extract every different job
    groupNameData = _.pluck(@prenodes, groupIdentifier)
    @groups = _.uniq(groupNameData)

    # Create a d3 range to get a different color for every group.
    # To get nice color, we use colorbrewer
    @fillGroupColor = d3.scale.ordinal()
                      .domain(@groups)
                      .range(["#0395D0", "#F8DE81", "#E1316F", "#59E898", "#888371"]);


  # Get every employee new enterprises to create a list.
  # This list will be use to define a center (x,y) for every different enterprise.
  createEnterprises: () =>
    # Extract every different enterprises
    enterprisesNames = _.pluck(@prenodes, "futurEnterprise")
    enterprises = _.shuffle(_.uniq(enterprisesNames))

    # Get the angle to distribute every enterprises around a circle
    angle = 360 / (enterprises.length)  # minus 1 because OWNI is in the center

    # Owni will stay in the center
    @enterpriseCenters =
      Owni :
        x : @graphSettings.circleCenter.x
        y : @graphSettings.circleCenter.y
        added : true

    # Let go for the Maths !
    # For every enterprise, let get the new center, moving the previous center of x deg
    enterprises.forEach (enterprise, i) =>
      unless enterprise == "Owni" or not enterprise
        @enterpriseCenters[enterprise] =
          x : @graphSettings.circleCenter.x + Math.cos( i * angle * Math.PI/180) * @graphSettings.circleRadius
          y : @graphSettings.circleCenter.y - Math.sin( i * angle * Math.PI/180) * @graphSettings.circleRadius

  # Create the SVG visualization container
  createVis: () =>
    d3.select(".container-fluid svg").remove()

    # Create the SVG container
    @vis = d3.select(".container-fluid")
              .append("svg")
              .attr("width", @graphSettings.width)
              .attr("height", @graphSettings.height)

    # Insert every twitter image to pre-load images
    @vis.selectAll("image")
      .data(@prenodes)
      .enter().append("image")
        .attr("xlink:href", (d) =>
          if d.twitterAccount
            "https://api.twitter.com/1/users/profile_image?size=bigger&screen_name=#{d.twitterAccount}"
          else
            "images/default-avatar.png"
        )
        .attr("x", (d) => @graphSettings.width * 2)
        .attr("y", (d) => @graphSettings.height * 2)

    # Show the timeline bar
    @vis.append("text")
          .attr("class", "current_date")
          .attr("width", 150)
          .attr("height", 20)
          .attr("x", "50%")
          .attr("y", "80%")

    # Add a legend on the left of the graphic
    legend = @vis.selectAll(".legend")
      .data(@groups)
      .enter().append("g")
        .attr("class", "legend")
        .attr("transform", (d, i) => "translate(22.5, #{180 + (i * 40)})")

    legend.append("circle")
      .attr("r", (d) -> 15)
      .attr("fill", (d) => @fillGroupColor(@groups.indexOf(d)))
      .attr("stroke-width", 2)
      .attr("stroke", (d) => d3.rgb(@fillGroupColor(@groups.indexOf(d))).darker())
      .attr("x", 10)
      .attr("y", 0)

    legend.append("text")
      .text((d) => d)
      .attr("x", 20)
      .attr("y", 2)

    # Update Visualization to display the first bubbles
    this.updateVis()


  # Update the visualization to add new bubbles
  updateVis: () =>
    that = this

    # Display the employee activity
    this.updateEmployeeChanges()

    # Add new bubbles
    @circles = @vis.selectAll("circle")
                    .data(@nodes, (d) -> d.id)
                    .enter().append("circle")
                      .attr("r", 0)
                      .attr("fill", (d) => @fillGroupColor(@groups.indexOf(d[@graphSettings.groupIdentifier])))
                      .attr("stroke-width", 2)
                      .attr("stroke", (d) => d3.rgb(@fillGroupColor(@groups.indexOf(d[@graphSettings.groupIdentifier]))).darker())
                      .attr("id", (d) -> "bubble_#{d.id}")
                      .on("mouseover", (d,i) -> that.show_details(d,i,this))
                      .on("mouseout", (d,i) -> that.hide_details(d,i,this))
                      .call(@force.drag);

    # Make new bubble grow from 0 to their regular radius
    @circles.transition()
            .duration(@graphSettings.animationSpeed)
              .attr("r", (d) -> d.radius)

    # Relaunch the force layout
    @force.start()


  # Display employee activity (in and out)
  updateEmployeeChanges: () =>
    # Remove all employee in the list
    d3.select(".employee-changes").selectAll(".employee")
      .remove()

    # Bind data for new employee activity
    employeeChanges = d3.select(".employee-changes").selectAll(".employee").data(@employeeChanges)

    # Add a new employee bloc
    newEmployee = employeeChanges.enter()
                    .append("div")
                      .attr("class", (d) =>
                  if d.currentEnterprise == "Owni"
                    return "employee in"
                  else
                    return "employee out"
                )

    # Add the icon depending the situation
    newEmployee.append("span")
                .attr("class", "action")

    # Add employee image and name
    newEmployee.append("img")
                .attr("src", (d) =>
                  if d.twitterAccount
                    "https://api.twitter.com/1/users/profile_image?size=bigger&screen_name=#{d.twitterAccount}"
                  else
                    "images/default-avatar.png"
                )
                .attr("alt", (d) => d.name)
                .attr("height", 30)
                .attr("width", 30)
                .style("display", (d) =>
                  if d.twitterAccount
                    "block"
                  else
                    "none"
                )

    info = newEmployee.append("div")
                .attr("class", "info")
    info.append("div")
                .attr("class", "name")
                .text( (d) => d.name)
    info.append("div")
                .attr("class", "enterprise")
                .text( (d) => d.currentEnterprise)


  # Calculate the charge of a node depending its size
  charge: (d) =>
    -Math.pow(d.radius, 2.0) / 8


  # Define the new center of a node depending its enterprise
  moveTowardsCenter: (alpha) =>
    (d) =>
      center = @enterpriseCenters[d.currentEnterprise]
      if center
        d.x = d.x + (center.x - d.x) * (@graphSettings.damper + 0.02) * alpha * 1.1
        d.y = d.y + (center.y - d.y) * (@graphSettings.damper + 0.02) * alpha * 1.1
      else
        # We don't know the actual company, let's move it out of the graph
        d.x = @graphSettings.width * 2
        d.y = @graphSettings.height * 2


  # Display the tooltip with informations about the selected node
  show_details: (data, i, element) =>
    # Change the node stroke color
    d3.select(element).attr("stroke", (d) => d3.rgb(@fillGroupColor(@groups.indexOf(d[@graphSettings.groupIdentifier]))).darker(1.5))

    # Define tooltip content
    content = "<div class=\"title\"><strong>#{data.name}</strong> (@#{data.twitterAccount})</div>"
    if data.twitterAccount
      content +="<div class=\"pic\"><img src=\"https://api.twitter.com/1/users/profile_image?size=bigger&screen_name=#{data.twitterAccount}\" alt=\"#{data.name}\"/>"
    else
      content +="<div class=\"pic\"><img src=\"images/default-avatar.png\" alt=\"#{data.name}\"/>"
    content +="<div class=\"enterprise\">#{data.currentEnterprise}</div>"

    # Show the tooltip
    @tooltip.showTooltip(content,d3.event)


  # Hide the tooltip
  hide_details: (data, i, element) =>
    # Reset node color
    d3.select(element).attr("stroke", (d) => d3.rgb(@fillGroupColor(@groups.indexOf(d[@graphSettings.groupIdentifier]))).darker())
    @tooltip.hideTooltip()

  # Animate the visualization according to the current date
  animate: () =>
    # Reset employee changes
    @employeeChanges = []

    # Check if employee are leaving. If yes, update their enterprise
    @nodes.forEach  (node, i) =>
      if node.leavingDate and (node.leavingDate.year() == @currentDate.year()) and (node.leavingDate.month() == @currentDate.month())
        node.currentEnterprise = node.futurEnterprise
        @employeeChanges.push(node)

    # Check if new employee are hired
    @prenodes.forEach (node, i) =>
      if (node.added == false) and (node.hiringDate.year() == @currentDate.year()) and (node.hiringDate.month() == @currentDate.month())
        node.added = true
        @nodes.push(node)
        @employeeChanges.push(node)

    # Update the date displayed on the visualization
    @vis.select(".current_date").text(@currentDate.format("MMMM YYYY").toUpperCase())

    # Update the visualization with new data
    this.updateVis()

    # Increment the date of a month
    @currentDate.add('M', 1)
    @pastMonths++

    # If the next date is later than today, stop the animation
    if @currentDate > moment()
      clearTimeout(@timer)
    else
      # Evaluate the next timeout depending the employee activity
      nextTimeout = 0
      switch @employeeChanges.length
        when 0 then nextTimeout = @graphSettings.animationSpeed / 3
        when 1 then nextTimeout = @graphSettings.animationSpeed * 1.5
        when 2, 3 then nextTimeout = @graphSettings.animationSpeed * 2
        else nextTimeout = @graphSettings.animationSpeed * 3

      # Schedule the next animation
      @timer = setTimeout =>
          this.animate()
        , nextTimeout


$ ->
  # Store the CVS url
  #csv_file = "data/data.csv"
  root = exports ? this
  csv_file = "https://docs.google.com/spreadsheet/pub?key=0Aiw0tVQC3oLpdHVDUTVtN0R1LW1PNExrRXVGSVJ4R3c&single=true&gid=0&output=csv"

  render_vis = (csv) ->
    root.csv = csv
    root.chart = new OwniStory root.csv

  # Load the CVS file and render the visualization when it's done
  d3.csv csv_file, render_vis

  $(".replay").live("click", (d) => window.location.reload())